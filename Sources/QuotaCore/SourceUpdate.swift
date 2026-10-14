import CryptoKit
import Foundation
import Security

/// The source commit an app was built from, as scripts/build.sh records it in Info.plist.
public struct BuildInfo: Equatable, Sendable {
    public var commit: String?
    public var modified: Bool
    public init(commit: String?, modified: Bool = false) {
        self.commit = commit.flatMap(SourceUpdate.commit)
        self.modified = modified
    }
    public init(infoDictionary: [String: Any]?) {
        self.init(commit: infoDictionary?["JuiceBarSourceCommit"] as? String,
                  modified: infoDictionary?["JuiceBarSourceModified"] as? Bool ?? false)
    }
    public init(app: URL) {
        self.init(infoDictionary: NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])
    }
}

public enum UpdateStatus: Equatable, Sendable {
    case upToDate
    /// The branch has moved past this build.
    case available(String)
    /// The branch doesn't contain this build: one built from a branch ahead of it, or a release
    /// withdrawn with a force-push. It is never replaced, so nobody is downgraded.
    case development
    /// Built with uncommitted changes.
    case modified
    /// Built without a recorded commit.
    case unknownBuild
}

public enum UpdateError: Error, Equatable, Sendable {
    /// No Xcode or Command Line Tools.
    case tools
    /// The repository couldn't be reached or cloned.
    case download
    /// The repository has no such branch.
    case noBranch
    case build
    /// The built app isn't the expected commit, app or signature.
    case verify
    case install
    /// Another Juice Bar is updating.
    case busy
    case cancelled
}

public enum SourceUpdate {
    public static let repository = "https://github.com/mindtheflo/juice-bar.git"
    /// The branches an app can follow. Releases are commits pushed to `stable`; `nightly` is the
    /// development branch, with every change as soon as it is merged.
    public static let branches = ["stable", "nightly"]
    public static let defaultBranch = "stable"
    public static let interval: TimeInterval = 24 * 60 * 60
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Juice Bar", isDirectory: true)
    }

    /// A full commit hash in lowercase, or nil. Nothing else is ever passed to git as a commit.
    public static func commit(_ value: String) -> String? {
        let value = value.lowercased()
        return value.utf8.count == 40 && value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) ? value : nil
    }

    /// A plain branch name, which git can't take for an option or a pattern, or nil.
    public static func branch(_ value: String) -> String? {
        let plain = value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }
        return plain && value.first?.isLetter == true && value.utf8.count <= 64 && !value.contains("..")
            && !value.hasSuffix(".") && !value.hasSuffix(".lock") ? value : nil
    }

    public static func status(_ installed: BuildInfo, latest: String, installedIsAncestor: Bool) -> UpdateStatus {
        guard let commit = installed.commit else { return .unknownBuild }
        if installed.modified { return .modified }
        if commit == latest { return .upToDate }
        return installedIsAncestor ? .available(latest) : .development
    }

    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck else { return true }
        // A check dated in the future means the clock changed: check rather than wait for it.
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}

/// How an app is signed: the certificate its updates are signed with, and its team.
public struct CodeSignature: Equatable, Sendable {
    /// The SHA-1 of the signing certificate, as codesign accepts it, or "-" for an ad-hoc signature.
    public var identity: String
    public var team: String?
    public init(identity: String, team: String?) {
        self.identity = identity
        self.team = team
    }

    public static func running() -> CodeSignature? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return read(staticCode)
    }
    public static func of(_ app: URL) -> CodeSignature? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        return read(code)
    }
    /// Whether the app and everything nested in it is intact and validly signed.
    public static func isValid(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }
    private static func read(_ code: SecStaticCode) -> CodeSignature? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        guard let leaf = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first else {
            return CodeSignature(identity: "-", team: team)
        }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
        return CodeSignature(identity: digest.map { String(format: "%02X", $0) }.joined(), team: team)
    }
}

/// Updates Juice Bar from source. It follows a branch in a private clone, builds new commits with
/// their own scripts/build.sh, and swaps the result into place. Every call blocks:
/// run it off the main thread. Git never prompts: no terminal, askpass or credential helper, and
/// no user or system configuration, which could send GitHub requests to SSH.
public final class SourceUpdater: @unchecked Sendable {
    public let directory: URL
    public let repository: String
    private let lock = NSLock()
    private var running: Process?
    private var cancelled = false

    public init(directory: URL = SourceUpdate.directory, repository: String = SourceUpdate.repository) {
        self.directory = directory
        self.repository = repository
    }
    var source: URL { directory.appendingPathComponent("Source", isDirectory: true) }
    var output: URL { directory.appendingPathComponent("Build", isDirectory: true) }
    public var log: URL { directory.appendingPathComponent("update.log") }

    /// Compares a build with a branch. The clone is fetched only when the branch moved.
    public func check(_ installed: BuildInfo, branch: String) throws -> UpdateStatus {
        guard let commit = installed.commit else { return .unknownBuild }
        if installed.modified { return .modified }
        guard let branch = SourceUpdate.branch(branch) else { throw UpdateError.noBranch }
        return try locked { log in
            let tools = try developerDirectory(log)
            let ref = "refs/heads/" + branch
            let heads = try git(["ls-remote", "--heads", "--", repository, ref], tools: tools, log: log, timeout: 60)
            guard heads.status == 0 else { throw UpdateError.download }
            let remote = heads.output.split(separator: "\n").lazy.compactMap { line -> String? in
                let fields = line.split(separator: "\t")
                return fields.count == 2 && fields[1] == ref ? SourceUpdate.commit(String(fields[0])) : nil
            }.first
            guard let remote else { throw UpdateError.noBranch }
            note("check \(branch) at \(remote), running \(commit)", log)
            if remote == commit { return .upToDate }
            let latest = try fetch(branch, tools: tools, log: log)
            let ancestor = try latest != commit
                && git(["merge-base", "--is-ancestor", commit, latest], in: source, tools: tools, log: log).status == 0
            return SourceUpdate.status(installed, latest: latest, installedIsAncestor: ancestor)
        }
    }

    /// Builds a commit of the branch, signed like the running app, and checks the result.
    /// Returns the app, ready for `install`.
    public func build(_ commit: String, branch: String, signature: CodeSignature, bundleIdentifier: String) throws -> URL {
        guard let commit = SourceUpdate.commit(commit), let branch = SourceUpdate.branch(branch) else { throw UpdateError.verify }
        return try locked { log in
            let tools = try developerDirectory(log)
            let present = try FileManager.default.fileExists(atPath: source.appendingPathComponent(".git/HEAD").path)
                && git(["cat-file", "-e", commit + "^{commit}"], in: source, tools: tools, log: log).status == 0
            if !present { _ = try fetch(branch, tools: tools, log: log) }
            // Ignored files stay: the previous build folder makes this build incremental.
            guard try git(["checkout", "--quiet", "--force", "-B", branch, commit], in: source, tools: tools, log: log).status == 0,
                  try git(["clean", "-ffdq"], in: source, tools: tools, log: log).status == 0 else { throw UpdateError.build }
            let environment = Self.environment(["CODESIGN_IDENTITY": signature.identity, "DEVELOPER_DIR": tools.path])
            var built = false
            // A failure is retried once from a clean build folder, which may be stale after a toolchain update.
            for attempt in 0..<2 where !built {
                if attempt > 0 { try? FileManager.default.removeItem(at: source.appendingPathComponent(".build")) }
                try? FileManager.default.removeItem(at: output)
                note("build \(commit)", log)
                built = try run(URL(fileURLWithPath: "/bin/bash"), [source.appendingPathComponent("scripts/build.sh").path, output.path],
                                in: source, environment: environment, timeout: 20 * 60, log: log, capture: false).status == 0
            }
            guard built else { throw UpdateError.build }
            let app = output.appendingPathComponent("Juice Bar.app", isDirectory: true)
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == bundleIdentifier,
                  info?["CFBundleExecutable"] as? String == "cpamc-menubar",
                  BuildInfo(infoDictionary: info) == BuildInfo(commit: commit),
                  CodeSignature.isValid(app), CodeSignature.of(app)?.team == signature.team else { throw UpdateError.verify }
            return app
        }
    }

    /// Replaces the installed app with a built one in a single rename, so it is never missing or
    /// half-copied. Nothing is replaced if the installed app isn't the `running` commit any more,
    /// for example after a reinstall by hand.
    public func install(_ app: URL, replacing installed: URL, running: String) throws {
        try locked { log in
            guard BuildInfo(app: installed).commit == SourceUpdate.commit(running) else { throw UpdateError.install }
            let fm = FileManager.default
            let folder = installed.deletingLastPathComponent()
            let name = installed.deletingPathExtension().lastPathComponent
            let pid = ProcessInfo.processInfo.processIdentifier
            let staged = folder.appendingPathComponent(".\(name).update-\(pid)", isDirectory: true)
            try? fm.removeItem(at: staged)
            defer { try? fm.removeItem(at: staged) }
            guard try run(URL(fileURLWithPath: "/usr/bin/ditto"), [app.path, staged.path], environment: Self.environment(),
                          timeout: 120, log: log).status == 0, CodeSignature.isValid(staged) else { throw UpdateError.install }
            note("install \(BuildInfo(app: staged).commit ?? "?")", log)
            // The previous app ends up at the staging path, which is then deleted.
            if renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 { return }
            // Volumes without an atomic swap: move the previous app aside, then the new one in.
            let previous = folder.appendingPathComponent(".\(name).previous-\(pid)", isDirectory: true)
            try? fm.removeItem(at: previous)
            guard rename(installed.path, previous.path) == 0 else { throw UpdateError.install }
            guard rename(staged.path, installed.path) == 0 else {
                _ = rename(previous.path, installed.path)
                throw UpdateError.install
            }
            try? fm.removeItem(at: previous)
        }
    }

    /// Stops the command in progress, with every process it started, and refuses further work.
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let running, running.isRunning { Self.terminate(running) }
    }

    /// Brings the clone to the branch's latest commit and returns that commit.
    private func fetch(_ branch: String, tools: URL, log: FileHandle) throws -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: source.appendingPathComponent(".git/HEAD").path) {
            let refspec = "+refs/heads/\(branch):refs/remotes/origin/\(branch)"
            guard try git(["remote", "set-url", "origin", repository], in: source, tools: tools, log: log).status == 0,
                  try git(["fetch", "--quiet", "--no-tags", "origin", refspec], in: source, tools: tools, log: log).status == 0
            else { throw UpdateError.download }
        } else {
            let partial = directory.appendingPathComponent("Source.partial", isDirectory: true)
            try? fm.removeItem(at: partial)
            try? fm.removeItem(at: source)
            guard try git(["clone", "--quiet", "--branch", branch, "--single-branch", "--no-tags", "--", repository, partial.path],
                          tools: tools, log: log).status == 0 else { throw UpdateError.download }
            do { try fm.moveItem(at: partial, to: source) } catch { throw UpdateError.download }
        }
        let head = try git(["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(branch)^{commit}"], in: source, tools: tools, log: log)
        guard head.status == 0, let latest = SourceUpdate.commit(head.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw UpdateError.download
        }
        return latest
    }

    /// The active developer folder, whose own git is used. The /usr/bin shims would offer to install
    /// the Command Line Tools in a dialog rather than fail.
    private func developerDirectory(_ log: FileHandle) throws -> URL {
        let result = try run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"], environment: Self.environment(), timeout: 10, log: log)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path + "/usr/bin/git") else {
            throw UpdateError.tools
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func git(_ arguments: [String], in directory: URL? = nil, tools: URL, log: FileHandle,
                     timeout: TimeInterval = 300) throws -> (status: Int32, output: String) {
        try run(tools.appendingPathComponent("usr/bin/git"), ["-c", "credential.helper="] + arguments, in: directory,
                environment: Self.environment(), timeout: timeout, log: log)
    }

    private static func environment(_ extra: [String: String] = [:]) -> [String: String] {
        var environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                           "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false",
                           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_SSH_COMMAND": "ssh -o BatchMode=yes"]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["TMPDIR", "USER", "LOGNAME"] { environment[key] = inherited[key] }
        return environment.merging(extra) { $1 }
    }

    /// Runs a command with its errors (and output, unless captured) in the log.
    private func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil, environment: [String: String],
                     timeout: TimeInterval, log: FileHandle, capture: Bool = true) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.qualityOfService = .utility
        process.standardInput = FileHandle.nullDevice
        process.standardError = log
        let pipe = Pipe()
        process.standardOutput = capture ? pipe : log
        try lock.withLock {
            guard !cancelled else { throw UpdateError.cancelled }
            try process.run()
            running = process
        }
        let timer = DispatchWorkItem { if process.isRunning { Self.terminate(process) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        timer.cancel()
        try lock.withLock {
            running = nil
            if cancelled { throw UpdateError.cancelled }
        }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func terminate(_ process: Process) {
        // Each command leads its own process group: signal the group, so compilers and git helpers stop too.
        let group = -process.processIdentifier
        kill(group, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { kill(group, SIGKILL) }
    }

    /// Runs `body` while holding the update lock, with the log open for appending.
    private func locked<T>(_ body: (FileHandle) throws -> T) throws -> T {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The clone, build folder and log are all recreated when missing: keep them out of backups.
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let descriptor = Darwin.open(directory.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw UpdateError.install }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw UpdateError.busy }
        // One update's worth of output is plenty: the log starts over past 1 MB.
        if let size = (try? fm.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 1_000_000 { try? fm.removeItem(at: log) }
        let output = Darwin.open(log.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw UpdateError.install }
        let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        return try body(handle)
    }

    private func note(_ text: String, _ log: FileHandle) {
        try? log.write(contentsOf: Data("== \(ISO8601DateFormatter().string(from: Date())) \(text)\n".utf8))
    }
}
