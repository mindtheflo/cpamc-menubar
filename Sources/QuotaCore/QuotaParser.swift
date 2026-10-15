import Foundation

public enum QuotaParser {
    public static func record(_ value: JSONValue, previous: SubscriptionAccount? = nil) -> SubscriptionAccount? {
        guard let raw = value["provider"].string ?? value["type"].string,
              let provider = Provider(rawValue: raw.lowercased()), let id = value["auth_index"].string, !id.isEmpty else { return nil }
        // The sign-in email names an account best; the proxy's label and account id are fallbacks.
        let label = [value["email"].string, value["label"].string, value["account"].string]
            .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? provider.title
        var result = previous ?? SubscriptionAccount(id: id, provider: provider, label: label)
        result.label = label; result.disabled = isDisabled(value)
        result.unavailable = value["unavailable"].bool ?? false
        result.cooldownUntil = parseDate(value["next_retry_after"].string)
        let quota = value["quota"]
        if let observed = parseDate(quota["observed_at"].string) {
            let parsed = headerWindows(provider: provider, signals: quota["signals"], at: observed)
            if !parsed.isEmpty, observed > (result.checkedAt ?? .distantPast) {
                // Keep additional windows from a direct read, but replace shared windows with newer receipts.
                result.windows = parsed + result.windows.filter { old in !parsed.contains { $0.id == old.id } }
            }
            if provider == .codex, result.plan == nil { result.plan = planLabel(quota["signals"]["X-Codex-Plan-Type"].string) }
        }
        return result
    }

    /// Disabled as the proxy decides it: the account's switch is off, or its status says it is disabled.
    public static func isDisabled(_ record: JSONValue) -> Bool {
        record["disabled"].bool == true || record["status"].string == "disabled"
    }

    public static func headerWindows(provider: Provider, signals: JSONValue, at date: Date) -> [QuotaWindow] {
        if provider == .claude {
            return [("five_hour", "5h"), ("seven_day", "7d")].compactMap { id, tag in
                guard let fraction = signals["Anthropic-Ratelimit-Unified-\(tag)-Utilization"].number else { return nil }
                let reset = signals["Anthropic-Ratelimit-Unified-\(tag)-Reset"].number.map { Date(timeIntervalSince1970: $0) }
                return .init(id: id, usedPercent: fraction * 100, resetsAt: reset, observedAt: date)
            }
        }
        return [("primary", "Primary"), ("secondary", "Secondary")].compactMap { fallback, tag in
            guard let minutes = signals["X-Codex-\(tag)-Window-Minutes"].number, minutes > 0,
                  let used = signals["X-Codex-\(tag)-Used-Percent"].number else { return nil }
            let reset = signals["X-Codex-\(tag)-Reset-At"].number.map { Date(timeIntervalSince1970: $0) }
            return .init(id: windowID(seconds: minutes * 60, fallback: fallback), usedPercent: used, resetsAt: reset, observedAt: date)
        }
    }

    public static func applyClaude(_ usage: JSONValue, profile: JSONValue?, to account: SubscriptionAccount, at now: Date) -> SubscriptionAccount {
        var result = account
        let ids = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps", "seven_day_cowork"]
        let windows: [QuotaWindow] = ids.compactMap { id in
            let value = usage[id]
            guard case .object = value else { return nil }
            return .init(id: id, usedPercent: value["utilization"].number,
                         resetsAt: parseDate(value["resets_at"].string), observedAt: now,
                         modelScoped: !["five_hour", "seven_day"].contains(id))
        }
        result.windows = windows; result.checkedAt = now
        result.readError = windows.isEmpty ? ProxyError.malformed.localizedDescription : nil
        result.extraUsageEnabled = usage["extra_usage"]["is_enabled"].bool
        if let tier = profile?["organization"]["rate_limit_tier"].string { result.plan = planLabel(tier) }
        if let eligible = usage["cedar_ember"]["eligible"].bool {
            result.resetGrantsLeft = eligible ? usage["cedar_ember"]["grants"].array.reduce(0) {
                $0 + Int($1["resets_left"].number ?? 0)
            } : 0
        }
        return result
    }

    public static func applyCodex(_ usage: JSONValue, to account: SubscriptionAccount, at now: Date) -> SubscriptionAccount {
        var result = account
        let limits = usage["rate_limit"]
        result.windows = [("primary_window", "primary"), ("secondary_window", "secondary")].compactMap { key, fallback in
            let w = limits[key]
            guard case .object = w, let seconds = w["limit_window_seconds"].number, seconds > 0 else { return nil }
            let reset = w["reset_at"].number.map { Date(timeIntervalSince1970: $0) }
            return .init(id: windowID(seconds: seconds, fallback: fallback), usedPercent: w["used_percent"].number,
                         resetsAt: reset, observedAt: now)
        }
        result.plan = planLabel(usage["plan_type"].string) ?? result.plan
        result.checkedAt = now
        result.readError = result.windows.isEmpty ? ProxyError.malformed.localizedDescription : nil
        result.paidCredits = usage["credits"]["balance"].number
        result.unlimitedCredits = usage["credits"]["unlimited"].bool ?? false
        return result
    }

    public static func chatGPTAccountID(_ record: JSONValue) -> String? {
        let claims = record["id_token"]
        return record["chatgpt_account_id"].string ?? claims["chatgpt_account_id"].string
            ?? claims["https://api.openai.com/auth"]["chatgpt_account_id"].string
    }
    public static func windowID(seconds: Double, fallback: String) -> String {
        seconds == 604800 ? "seven_day" : seconds == 18000 ? "five_hour" : fallback
    }
    public static func planLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if s.contains("max_20x") { return "Max 20×" }
        if s.contains("max_5x") { return "Max 5×" }
        if s.contains("max") { return "Max" }
        if s.contains("pro") { return "Pro" }
        if s.contains("plus") { return "Plus" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
