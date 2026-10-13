import Foundation

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the local management key to a redirect destination.
        completionHandler(nil)
    }
}

public actor ProxyClient {
    private let configuration: Configuration
    private let session: URLSession
    private var planChecked: [String: Date] = [:]
    private var probeAttempted: [String: Date] = [:]

    public init(configuration: Configuration) {
        self.configuration = configuration
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 35
        c.urlCache = nil; c.httpCookieStorage = nil
        c.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        self.session = URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }

    // Injection is internal, for management-API contract tests only.
    init(configuration: Configuration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    public func setAccountEnabled(_ account: SubscriptionAccount, enabled: Bool) async throws -> SubscriptionAccount {
        let initial = try await management(path: "auth-files")
        guard case .array(let records) = initial["files"],
              let record = records.first(where: { $0["auth_index"].string == account.id }),
              let current = QuotaParser.record(record, previous: account), current.provider == account.provider,
              let name = record["name"].string, !name.isEmpty,
              let disabled = record["disabled"].bool else { throw ProxyError.accountUpdate }
        if disabled == !enabled { return current }
        let body: JSONValue = .object(["name": .string(name), "auth_index": .string(account.id), "disabled": .bool(!enabled)])
        var writeError: Error?
        do { _ = try await management(path: "auth-files/status", body: body, method: "PATCH") }
        catch { writeError = error }
        // Reconcile even a lost PATCH response. Never blindly repeat a routing mutation.
        let response = try await management(path: "auth-files")
        guard let updated = response["files"].array.first(where: { $0["auth_index"].string == account.id }),
              updated["disabled"].bool == !enabled,
              let result = QuotaParser.record(updated, previous: account), result.provider == account.provider else {
            throw writeError ?? ProxyError.accountUpdate
        }
        return result
    }

    public func fetch(previous: QuotaSnapshot? = nil, force: Bool = false) async throws -> QuotaSnapshot {
        let now = Date()
        let response = try await management(path: "auth-files")
        guard case .array(let records) = response["files"] else { throw ProxyError.malformed }
        let known = Dictionary(uniqueKeysWithValues: (previous?.accounts ?? []).map { ($0.id, $0) })
        var results: [SubscriptionAccount] = []
        // Actors serialize bookkeeping; network calls suspend, allowing independent accounts to overlap.
        return await withTaskGroup(of: SubscriptionAccount?.self) { group in
            for record in records {
                guard let account = QuotaParser.record(record, previous: known[record["auth_index"].string ?? ""]) else { continue }
                let elapsed = now.timeIntervalSince(account.checkedAt ?? .distantPast)
                let attemptAge = now.timeIntervalSince(probeAttempted[account.id] ?? .distantPast)
                let resetPassed = account.windows.contains { !$0.isFresh(at: now) }
                let due = account.checkedAt == nil || elapsed >= Double(configuration.providerRefreshSeconds) || resetPassed
                if attemptAge >= 30 && (force || due) {
                    probeAttempted[account.id] = now
                    let fetchPlan = account.plan == nil || now.timeIntervalSince(planChecked[account.id] ?? .distantPast) > 86400
                    group.addTask { await self.probe(record, account: account, at: now, fetchPlan: fetchPlan) }
                } else { results.append(account) }
            }
            for await account in group { if let account { results.append(account) } }
            return QuotaSnapshot(accounts: results.sorted {
                $0.provider == $1.provider ? $0.label.localizedStandardCompare($1.label) == .orderedAscending : $0.provider == .codex
            }, fetchedAt: now)
        }
    }

    public func testConnection() async throws -> Int {
        let response = try await management(path: "auth-files")
        guard case .array(let records) = response["files"] else { throw ProxyError.malformed }
        return records.compactMap { QuotaParser.record($0) }.count
    }

    private func probe(_ record: JSONValue, account: SubscriptionAccount, at now: Date, fetchPlan: Bool) async -> SubscriptionAccount {
        do {
            if account.provider == .claude {
                let usage = try await upstream(account: account, route: .claudeUsage)
                var profile: JSONValue?
                if fetchPlan {
                    profile = try? await upstream(account: account, route: .claudeProfile)
                    if profile != nil { planChecked[account.id] = now }
                }
                return QuotaParser.applyClaude(usage, profile: profile, to: account, at: now)
            }
            let usage = try await upstream(account: account, route: .codexUsage,
                                           chatGPTAccountID: QuotaParser.chatGPTAccountID(record))
            return QuotaParser.applyCodex(usage, to: account, at: now)
        } catch {
            var result = account
            result.readError = (error as? ProxyError)?.localizedDescription ?? ProxyError.unavailable.localizedDescription
            return result
        }
    }

    // Quota routes are GET-only; the explicit account toggle is the sole credential-state mutation.
    private enum ReadRoute {
        case claudeUsage, claudeProfile, codexUsage
        var url: String {
            switch self {
            case .claudeUsage: return "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1"
            case .claudeProfile: return "https://api.anthropic.com/api/oauth/profile"
            case .codexUsage: return "https://chatgpt.com/backend-api/wham/usage"
            }
        }
    }
    private func upstream(account: SubscriptionAccount, route: ReadRoute, chatGPTAccountID: String? = nil) async throws -> JSONValue {
        var headers: [String: JSONValue] = ["Authorization": .string("Bearer $TOKEN$"), "Content-Type": .string("application/json")]
        if account.provider == .claude {
            headers["anthropic-beta"] = .string("oauth-2025-04-20")
            headers["User-Agent"] = .string("claude-cli/2.1.280 (external, cli)")
        } else {
            headers["User-Agent"] = .string("codex-tui/0.149.1 (Mac OS; arm64)")
            if let chatGPTAccountID { headers["Chatgpt-Account-Id"] = .string(chatGPTAccountID) }
        }
        let body: JSONValue = .object(["auth_index": .string(account.id), "method": .string("GET"),
                                      "url": .string(route.url), "header": .object(headers)])
        let response = try await management(path: "api-call", body: body)
        guard let status = response["status_code"].number else { throw ProxyError.malformed }
        guard (200..<300).contains(Int(status)) else { throw ProxyError.upstream(Int(status)) }
        guard let raw = response["body"].string, let data = raw.data(using: .utf8) else { throw ProxyError.malformed }
        do { return try JSONValue.decode(data) } catch { throw ProxyError.malformed }
    }

    private func management(path: String, body: JSONValue? = nil, method: String = "POST") async throws -> JSONValue {
        let base = try configuration.validatedURL()
        guard let key = try? String(contentsOf: configuration.keyFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
              !key.contains("\n"), !key.contains("\r") else { throw ProxyError.missingKey }
        let url = base.appendingPathComponent("v0/management/" + path)
        var request = URLRequest(url: url)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = method; request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ProxyError.unavailable }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ProxyError.malformed }
        guard (200..<300).contains(status) else { throw ProxyError.rejected(status) }
        guard data.count <= 10_000_000 else { throw ProxyError.malformed }
        do { return try JSONValue.decode(data) } catch { throw ProxyError.malformed }
    }
}
