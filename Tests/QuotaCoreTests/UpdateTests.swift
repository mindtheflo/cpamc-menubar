import XCTest
@testable import QuotaCore

final class UpdateTests: XCTestCase {
    func testBuildInfoKeepsOnlyFullCommits() {
        let commit = String(repeating: "a1", count: 20)
        XCTAssertEqual(BuildInfo(commit: commit.uppercased()).commit, commit)
        XCTAssertNil(BuildInfo(commit: "a1b2c3").commit)
        XCTAssertNil(BuildInfo(commit: "-" + commit.dropFirst()).commit)
        XCTAssertNil(BuildInfo(commit: String(repeating: "g", count: 40)).commit)
        XCTAssertEqual(BuildInfo(infoDictionary: ["JuiceBarSourceCommit": commit, "JuiceBarSourceModified": true]),
                       BuildInfo(commit: commit, modified: true))
        XCTAssertEqual(BuildInfo(infoDictionary: nil), BuildInfo(commit: nil))
    }

    func testOnlyCleanReleaseBuildsMoveForward() {
        let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40)
        XCTAssertEqual(SourceUpdate.status(BuildInfo(commit: a), latest: a, installedIsAncestor: true), .upToDate)
        XCTAssertEqual(SourceUpdate.status(BuildInfo(commit: a), latest: b, installedIsAncestor: true), .available(b))
        XCTAssertEqual(SourceUpdate.status(BuildInfo(commit: a), latest: b, installedIsAncestor: false), .development)
        XCTAssertEqual(SourceUpdate.status(BuildInfo(commit: a, modified: true), latest: b, installedIsAncestor: true), .modified)
        XCTAssertEqual(SourceUpdate.status(BuildInfo(commit: nil), latest: b, installedIsAncestor: true), .unknownBuild)
    }

    func testChecksOnceADay() {
        let now = Date()
        XCTAssertTrue(SourceUpdate.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(SourceUpdate.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(SourceUpdate.isDue(lastCheck: now.addingTimeInterval(-SourceUpdate.interval), now: now))
        XCTAssertTrue(SourceUpdate.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}

/// Runs the updater against a local repository whose build script makes a tiny signed app.
final class SourceUpdaterTests: XCTestCase {
    private var root: URL!
    private var gitBinary: URL!
    private var work: URL { root.appendingPathComponent("work", isDirectory: true) }
    private var origin: URL { root.appendingPathComponent("origin.git", isDirectory: true) }
    private var state: URL { root.appendingPathComponent("state", isDirectory: true) }
    private let adHoc = CodeSignature(identity: "-", team: nil)
    private let buildScript = """
        #!/bin/bash
        set -euo pipefail
        app="$1/Juice Bar.app"
        rm -rf "$app"
        mkdir -p "$app/Contents/MacOS"
        cp /usr/bin/true "$app/Contents/MacOS/cpamc-menubar"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $(cat bundle-id)" \\
          -c "Add :CFBundleExecutable string cpamc-menubar" -c "Add :CFBundlePackageType string APPL" \\
          -c "Add :JuiceBarSourceCommit string $(git rev-parse HEAD)" -c "Add :JuiceBarSourceModified bool false" \\
          "$app/Contents/Info.plist"
        codesign --force --sign "$CODESIGN_IDENTITY" "$app"
        """

    override func setUpWithError() throws {
        let tools = try? run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
        gitBinary = URL(fileURLWithPath: (tools ?? "/nonexistent") + "/usr/bin/git")
        guard FileManager.default.isExecutableFile(atPath: gitBinary.path) else { throw XCTSkip("git is not installed") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", origin.path], in: root)
        try git(["init", "-q", work.path], in: root)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testFollowsTheBranchAndSwapsInNewBuilds() throws {
        let updater = SourceUpdater(directory: state, repository: origin.path)
        let a = try release(["scripts/build.sh": buildScript, "bundle-id": "test.juice-bar"])
        XCTAssertEqual(try updater.check(BuildInfo(commit: a), branch: "stable"), .upToDate)
        let b = try release(["notes.txt": "second release"])
        XCTAssertEqual(try updater.check(BuildInfo(commit: a), branch: "stable"), .available(b))

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let installed = applications.appendingPathComponent("Juice Bar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: updater.build(a, branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar"),
                                         to: installed)
        let built = try updater.build(b, branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar")
        XCTAssertEqual(BuildInfo(app: built), BuildInfo(commit: b))
        XCTAssertTrue(CodeSignature.isValid(built))

        try updater.install(built, replacing: installed, running: a)
        XCTAssertEqual(BuildInfo(app: installed), BuildInfo(commit: b))
        XCTAssertTrue(CodeSignature.isValid(installed))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: applications.path), ["Juice Bar.app"])
        // The app on disk is no longer the one running: it was replaced by hand.
        XCTAssertThrowsError(try updater.install(built, replacing: installed, running: a)) { XCTAssertEqual($0 as? UpdateError, .install) }
    }

    func testSwitchesBranchesWithoutGoingBack() throws {
        let updater = SourceUpdater(directory: state, repository: origin.path)
        let a = try release(["scripts/build.sh": buildScript, "bundle-id": "test.juice-bar"])
        try publish("nightly")
        let n = try commit(["notes.txt": "merged change"])
        try publish("nightly")

        // Stable to Nightly: the change merged since the release is installed right away.
        XCTAssertEqual(try updater.check(BuildInfo(commit: a), branch: "nightly"), .available(n))
        let built = try updater.build(n, branch: "nightly", signature: adHoc, bundleIdentifier: "test.juice-bar")
        XCTAssertEqual(BuildInfo(app: built), BuildInfo(commit: n))
        // Nightly back to Stable: the newer build stays until Stable includes it, then follows Stable.
        XCTAssertEqual(try updater.check(BuildInfo(commit: n), branch: "stable"), .development)
        try publish("stable")
        XCTAssertEqual(try updater.check(BuildInfo(commit: n), branch: "stable"), .upToDate)
        let r = try release(["notes.txt": "next release"])
        XCTAssertEqual(try updater.check(BuildInfo(commit: n), branch: "stable"), .available(r))
        XCTAssertEqual(BuildInfo(app: try updater.build(r, branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar")),
                       BuildInfo(commit: r))
    }

    func testNeverDowngradesOrReplacesOtherBuilds() throws {
        let updater = SourceUpdater(directory: state, repository: origin.path)
        let a = try release(["scripts/build.sh": buildScript, "bundle-id": "test.juice-bar"])
        let b = try release(["notes.txt": "withdrawn release"])
        XCTAssertEqual(try updater.check(BuildInfo(commit: a), branch: "stable"), .available(b))

        try git(["checkout", "-q", "-b", "feature"])
        let feature = try commit(["notes.txt": "work in progress"])
        XCTAssertEqual(try updater.check(BuildInfo(commit: feature), branch: "stable"), .development)
        XCTAssertEqual(try updater.check(BuildInfo(commit: feature, modified: true), branch: "stable"), .modified)
        XCTAssertEqual(try updater.check(BuildInfo(commit: nil), branch: "stable"), .unknownBuild)

        // A force-push withdraws b: its users keep it rather than going back or sideways.
        try git(["checkout", "-q", "-B", "nightly", a])
        let c = try release(["notes.txt": "replacement release"], force: true)
        XCTAssertEqual(try updater.check(BuildInfo(commit: b), branch: "stable"), .development)
        XCTAssertEqual(try updater.check(BuildInfo(commit: a), branch: "stable"), .available(c))
    }

    func testReportsWhatStopsAnUpdate() throws {
        let updater = SourceUpdater(directory: state, repository: origin.path)
        let a = try release(["scripts/build.sh": buildScript, "bundle-id": "test.juice-bar"])
        XCTAssertThrowsError(try updater.check(BuildInfo(commit: a), branch: "missing")) { XCTAssertEqual($0 as? UpdateError, .noBranch) }
        let unreachable = root.appendingPathComponent("missing.git").path
        XCTAssertThrowsError(try SourceUpdater(directory: state, repository: unreachable).check(BuildInfo(commit: a), branch: "stable")) {
            XCTAssertEqual($0 as? UpdateError, .download)
        }
        // Only a plain name reaches git, never an option or a pattern.
        for name in ["--upload-pack=touch", "-b", "*", "stable/../nightly", "Stable", "", "stable.lock"] {
            XCTAssertNil(SourceUpdate.branch(name))
            XCTAssertThrowsError(try updater.check(BuildInfo(commit: a), branch: name)) { XCTAssertEqual($0 as? UpdateError, .noBranch) }
            XCTAssertThrowsError(try updater.build(a, branch: name, signature: adHoc, bundleIdentifier: "test.juice-bar")) {
                XCTAssertEqual($0 as? UpdateError, .verify)
            }
        }
        XCTAssertEqual(SourceUpdate.branches.compactMap(SourceUpdate.branch), SourceUpdate.branches)

        let otherApp = try release(["bundle-id": "test.other-app"])
        XCTAssertThrowsError(try updater.build(otherApp, branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar")) {
            XCTAssertEqual($0 as? UpdateError, .verify)
        }
        let broken = try release(["scripts/build.sh": "exit 1\n"])
        XCTAssertThrowsError(try updater.build(broken, branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar")) {
            XCTAssertEqual($0 as? UpdateError, .build)
        }
        XCTAssertThrowsError(try updater.build("--help", branch: "stable", signature: adHoc, bundleIdentifier: "test.juice-bar")) {
            XCTAssertEqual($0 as? UpdateError, .verify)
        }

        let lock = open(state.appendingPathComponent(".lock").path, O_RDWR | O_CREAT, 0o600)
        XCTAssertEqual(flock(lock, LOCK_EX), 0)
        XCTAssertThrowsError(try updater.check(BuildInfo(commit: a), branch: "stable")) { XCTAssertEqual($0 as? UpdateError, .busy) }
        close(lock)

        updater.cancel()
        XCTAssertThrowsError(try updater.check(BuildInfo(commit: a), branch: "stable")) { XCTAssertEqual($0 as? UpdateError, .cancelled) }
    }

    /// Commits the files on the current branch and publishes the commit as a release.
    private func release(_ files: [String: String], force: Bool = false) throws -> String {
        let commit = try commit(files)
        try publish("stable", force: force)
        return commit
    }

    /// Pushes the current commit to a branch of the origin.
    private func publish(_ branch: String, force: Bool = false) throws {
        try git(["push", "-q"] + (force ? ["--force"] : []) + [origin.path, "HEAD:refs/heads/" + branch])
    }

    private func commit(_ files: [String: String]) throws -> String {
        for (path, content) in files {
            let file = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "Update \(files.keys.sorted().joined(separator: ", "))"])
        return try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL? = nil) throws -> String {
        try run(gitBinary, ["-c", "user.name=Juice Bar Tests", "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false",
                      "-c", "init.defaultBranch=nightly"] + arguments, in: directory ?? work)
    }

    /// Runs a command without the user's git configuration and fails on a non-zero exit.
    private func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ["HOME": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "/dev/null",
                               "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(executable.lastPathComponent) \(arguments.joined(separator: " ")) failed"])
        }
        return output
    }
}
