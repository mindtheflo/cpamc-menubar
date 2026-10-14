import AppKit
import Foundation
import QuotaCore

/// Keeps Juice Bar up to date from the branch it follows: a daily check, a build on this Mac, and a
/// restart while the menu is closed. Only a clean build of a commit on that branch is ever replaced.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, current, development, modified, unknownBuild
        /// The app can't replace itself where it is, outside an Applications folder.
        case unsupported
        case available(String), installing(String)
        /// Built and waiting for a restart.
        case ready(String)
        case failed(UpdateError)
    }
    @Published private(set) var phase: Phase
    @Published private(set) var lastCheck: Date?
    @Published var automatic: Bool {
        didSet {
            UserDefaults.standard.set(automatic, forKey: "autoUpdate")
            if automatic, case .available = phase { Task { await install() } } else { checkIfDue() }
        }
    }
    /// The branch to follow, one of `SourceUpdate.branches`.
    @Published var branch: String {
        didSet {
            UserDefaults.standard.set(branch, forKey: "updateBranch")
            guard branch != oldValue else { return }
            // A commit found on the previous branch no longer applies, and this one may be ahead:
            // compare with it now rather than at tomorrow's check.
            if case .available = phase { phase = .idle }
            retryAfter = nil
            Task { await check() }
        }
    }
    /// Whether a restart would go unnoticed: set by the app to the menu being closed.
    var canRestart: () -> Bool = { true }
    let version: String
    let build: BuildInfo
    private let demo: Bool
    /// The installed app, when it can replace itself.
    private let app: URL?
    private let engine = SourceUpdater()
    private var staged: URL?
    /// After a failed download, the next attempt waits until then rather than until tomorrow.
    private var retryAfter: Date?
    private var loop: Task<Void, Never>?

    init(demo: Bool) {
        self.demo = demo
        let info = Bundle.main.infoDictionary
        version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        build = BuildInfo(infoDictionary: info)
        automatic = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        let branch = UserDefaults.standard.string(forKey: "updateBranch") ?? ""
        self.branch = SourceUpdate.branches.contains(branch) ? branch : SourceUpdate.defaultBranch
        lastCheck = demo ? Date() : UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
        let bundle = Bundle.main.bundleURL
        let folder = bundle.deletingLastPathComponent()
        app = bundle.pathExtension == "app" && folder.lastPathComponent == "Applications"
            && FileManager.default.isWritableFile(atPath: folder.path) ? bundle : nil
        phase = demo ? .current : build.commit == nil ? .unknownBuild : build.modified ? .modified : app == nil ? .unsupported : .idle
    }

    /// The version as shown in Settings, with the commit it was built from.
    var versionDescription: String {
        guard let commit = build.commit else { return version }
        return "\(version) (\(commit.prefix(7))\(build.modified ? "+" : ""))"
    }
    var isBusy: Bool {
        switch phase {
        case .checking, .installing, .ready: true
        default: false
        }
    }
    /// Whether this build is one the updater can replace.
    var isUpdatable: Bool {
        switch phase {
        case .modified, .unknownBuild, .unsupported: false
        default: true
        }
    }
    var canCheck: Bool { isUpdatable && !demo && !isBusy }

    func start() {
        guard loop == nil, canCheck else { return }
        loop = Task { [weak self] in
            // Leave launch, and a login's busy first minutes, to everything else.
            try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            while !Task.isCancelled {
                self?.restartIfReady()
                self?.checkIfDue()
                try? await Task.sleep(nanoseconds: 1800 * 1_000_000_000)
            }
        }
    }
    func stop() {
        loop?.cancel()
        loop = nil
        engine.cancel()
    }

    func checkIfDue() {
        let now = Date()
        guard automatic, canCheck, SourceUpdate.isDue(lastCheck: lastCheck, now: now),
              retryAfter.map({ now >= $0 }) ?? true else { return }
        Task { await check() }
    }

    func check() async {
        guard canCheck else { return }
        phase = .checking
        let engine = engine, build = build, branch = branch
        let result = await Task.detached(priority: .utility) { Result { try engine.check(build, branch: branch) } }.value
        switch result {
        case .success(let status):
            record()
            switch status {
            case .upToDate: phase = .current
            case .available(let commit):
                phase = .available(commit)
                if automatic { await install() }
            case .development: phase = .development
            case .modified: phase = .modified
            case .unknownBuild: phase = .unknownBuild
            }
        case .failure(let error): fail(error as? UpdateError ?? .download)
        }
    }

    /// Builds the available release. It replaces this app at the next restart.
    func install() async {
        guard case .available(let commit) = phase else { return }
        phase = .installing(commit)
        guard let signature = CodeSignature.running() else { return fail(.verify) }
        let engine = engine, branch = branch, identifier = Bundle.main.bundleIdentifier ?? ""
        let result = await Task.detached(priority: .utility) {
            Result { try engine.build(commit, branch: branch, signature: signature, bundleIdentifier: identifier) }
        }.value
        switch result {
        case .success(let built):
            staged = built
            phase = .ready(commit)
            restartIfReady()
        case .failure(let error): fail(error as? UpdateError ?? .build)
        }
    }

    func restartIfReady() {
        guard case .ready = phase, canRestart() else { return }
        restart()
    }

    /// Swaps the new build into place and relaunches it, without taking focus.
    func restart() {
        guard case .ready = phase, let staged, let app, let running = build.commit else { return }
        // The helper outlives this process: it waits for it to exit, then opens the new app.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -g \"$2\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        do {
            try helper.run()
            try engine.install(staged, replacing: app, running: running)
        } catch {
            if helper.isRunning { helper.terminate() }
            self.staged = nil
            return fail(.install)
        }
        NSApp.terminate(nil)
    }

    private func fail(_ error: UpdateError) {
        guard error != .cancelled else { return }
        phase = .failed(error)
        // A network or lock problem is worth another try soon; anything else waits for tomorrow's check.
        if error == .download || error == .busy {
            retryAfter = Date().addingTimeInterval(60 * 60)
        } else {
            record()
        }
    }
    private func record() {
        retryAfter = nil
        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: "lastUpdateCheck")
    }
}
