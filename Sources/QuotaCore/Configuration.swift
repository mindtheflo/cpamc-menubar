import Foundation

public enum ProxyError: Error, LocalizedError, Sendable {
    case invalidEndpoint, missingKey, rejected(Int), malformed, upstream(Int), unavailable, accountUpdate
    public var errorDescription: String? {
        switch self {
        case .accountUpdate: return "The account change could not be confirmed. Refresh to check its current state."
        case .invalidEndpoint: return "Use a loopback proxy URL, such as http://127.0.0.1:8317."
        case .missingKey: return "Choose the local management-key file in Settings."
        case .rejected(let code): return "The local proxy returned HTTP \(code). Check the connection in Settings."
        case .malformed: return "The proxy returned an unreadable quota response."
        case .upstream(let code): return "Provider usage could not be read (HTTP \(code))."
        case .unavailable: return "The local proxy is not responding."
        }
    }
}

public struct Configuration: Codable, Sendable, Equatable {
    public var proxyURL: String
    public var managementKeyFile: String
    public var providerRefreshSeconds: Int
    public init(proxyURL: String = "http://127.0.0.1:8317", managementKeyFile: String? = nil, providerRefreshSeconds: Int = 300) {
        self.proxyURL = proxyURL
        self.managementKeyFile = managementKeyFile ?? "~/Library/Application Support/CLIProxyAPI/management-key"
        self.providerRefreshSeconds = providerRefreshSeconds
    }
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CPAMC Menu Bar/config.json")
    }
    public static func load() -> Configuration {
        guard let data = try? Data(contentsOf: fileURL), let c = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return c
    }
    public func validatedURL() throws -> URL {
        guard let c = URLComponents(string: proxyURL), let url = c.url,
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(c.host?.lowercased() ?? ""),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", (60...3600).contains(providerRefreshSeconds) else { throw ProxyError.invalidEndpoint }
        return url
    }
    public var paceHistorySource: String { proxyURL + "|" + keyFileURL.path }
    public var keyFileURL: URL {
        URL(fileURLWithPath: (managementKeyFile as NSString).expandingTildeInPath)
    }
    public var dashboardURL: URL? {
        try? validatedURL().appendingPathComponent("management.html").appending(fragment: "/quota")
    }
    public func save() throws {
        _ = try validatedURL()
        let fm = FileManager.default
        try fm.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}

private extension URL {
    func appending(fragment: String) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        c.fragment = fragment
        return c.url!
    }
}
