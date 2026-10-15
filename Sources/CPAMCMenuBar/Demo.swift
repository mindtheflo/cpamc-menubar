import Foundation
import QuotaCore

enum Demo {
    static func snapshot(at now: Date) -> QuotaSnapshot {
        // Accounts are named by their sign-in email, as the proxy reports it.
        let names = ["alex", "jordan", "morgan", "sam", "taylor"]
        func account(_ provider: Provider, _ number: Int, _ used: Double, hours: Double,
                     weekly: Double? = nil, disabled: Bool = false, idleSession: Bool = false) -> SubscriptionAccount {
            var windows = [QuotaWindow(id: weekly == nil ? "seven_day" : "five_hour", usedPercent: used,
                                       resetsAt: idleSession ? nil : now.addingTimeInterval(hours * 3600), observedAt: now)]
            if let weekly {
                windows.append(.init(id: "seven_day", usedPercent: weekly,
                                     resetsAt: now.addingTimeInterval(5 * 86400), observedAt: now))
            }
            return .init(id: "demo-\(provider.rawValue)-\(number)", provider: provider,
                         label: names[number - 1] + "@example.com", plan: provider == .claude ? "Max 20×" : "Pro",
                         disabled: disabled, unavailable: used >= 100 || (weekly ?? 0) >= 100,
                         cooldownUntil: used >= 100 ? now.addingTimeInterval(hours * 3600) : nil,
                         windows: windows, checkedAt: now,
                         extraUsageEnabled: provider == .claude ? false : nil,
                         paidCredits: provider == .codex ? 0 : nil, resetGrantsLeft: provider == .claude && number == 1 ? 1 : nil)
        }
        return .init(accounts: [
            account(.codex, 1, 31, hours: 162), account(.codex, 2, 4, hours: 165),
            account(.codex, 3, 0, hours: 150, disabled: true),
            account(.claude, 1, 0, hours: 4, weekly: 100, idleSession: true),
            account(.claude, 2, 100, hours: 0.5, weekly: 71),
            account(.claude, 3, 0, hours: 90, weekly: 100),
            account(.claude, 4, 37, hours: 1, weekly: 100),
            account(.claude, 5, 0, hours: 12, weekly: 100),
        ], fetchedAt: now)
    }
}
