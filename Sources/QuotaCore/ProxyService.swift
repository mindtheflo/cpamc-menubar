import Foundation

/// Limits service controls to the user's existing CLIProxyAPI installation.
public struct ProxyServiceDefinition: Sendable {
    public let plistURL: URL
    public let label: String
    public let domain: String
    public var target: String { domain + "/" + label }

    public init(plistURL: URL, data: Data, expectedRoot: URL, expectedPort: Int, configText: String, uid: UInt32) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String, label == "com.flo.cliproxyapi",
              let args = plist["ProgramArguments"] as? [String],
              args.first == expectedRoot.appendingPathComponent("bin/CLIProxyAPI").path,
              let index = args.firstIndex(where: { $0 == "--config" || $0 == "-config" }), args.indices.contains(index + 1),
              args[index + 1] == expectedRoot.appendingPathComponent("config.yaml").path else { throw ProxyControlError.unsupported }
        let port = configText.split(separator: "\n").compactMap { line -> Int? in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("port:") else { return nil }
            return Int(s.dropFirst(5).trimmingCharacters(in: .whitespaces))
        }.first
        guard port == expectedPort else { throw ProxyControlError.unsupported }
        self.plistURL = plistURL; self.label = label; self.domain = "gui/\(uid)"
    }

    public static func load(configuration: Configuration) throws -> Self {
        let endpoint = try configuration.validatedURL()
        let root = configuration.keyFileURL.deletingLastPathComponent()
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.flo.cliproxyapi.plist")
        return try Self(plistURL: plist, data: Data(contentsOf: plist), expectedRoot: root,
                        expectedPort: endpoint.port ?? (endpoint.scheme == "https" ? 443 : 80),
                        configText: String(contentsOf: root.appendingPathComponent("config.yaml"), encoding: .utf8), uid: getuid())
    }
}

public enum ProxyControlError: Error { case unsupported, commandFailed }

public enum ProxyService {
    private static func run(_ arguments: [String]) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments
            // launchctl print can include service environment; never collect or log it.
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
            process.waitUntilExit(); timeout.cancel()
            return process.terminationStatus
        }.value
    }
    public static func isRegistered(_ service: ProxyServiceDefinition) async -> Bool {
        (try? await run(["print", service.target])) == 0
    }
    public static func start(_ service: ProxyServiceDefinition) async throws {
        if !(await isRegistered(service)) {
            guard try await run(["bootstrap", service.domain, service.plistURL.path]) == 0 else { throw ProxyControlError.commandFailed }
        }
        // No -k: never restart an already running proxy.
        guard try await run(["kickstart", service.target]) == 0 else { throw ProxyControlError.commandFailed }
    }
    public static func stop(_ service: ProxyServiceDefinition) async throws {
        guard await isRegistered(service) else { return }
        guard try await run(["bootout", service.target]) == 0,
              !(await isRegistered(service)) else { throw ProxyControlError.commandFailed }
    }
}
