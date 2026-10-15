import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var title: String { self == .codex ? "Codex" : "Claude" }
}

public enum MeterTone: String, Codable, Sendable {
    case ok, low, out, unknown
    /// On pace to run out before the renewal.
    case overPace
    /// Well under pace: less than half used by the renewal.
    case underPace

    /// Used up; otherwise the pace, when it can be told; otherwise whether little is left.
    public init(left: Double, pace: Pace?) {
        if left <= 0 { self = .out; return }
        switch pace {
        case .over: self = .overPace
        case .under: self = .underPace
        case .steady: self = .ok
        case nil: self = left <= 10 ? .low : .ok
        }
    }
}

public struct QuotaWindow: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var usedPercent: Double?
    public var resetsAt: Date?
    public var observedAt: Date
    public var modelScoped: Bool

    public init(id: String, usedPercent: Double?, resetsAt: Date? = nil, observedAt: Date, modelScoped: Bool = false) {
        self.id = id
        self.usedPercent = usedPercent.flatMap { $0.isFinite && $0 >= 0 ? min(100, $0) : nil }
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.modelScoped = modelScoped
    }
    public var leftPercent: Double? { usedPercent.map { max(0, 100 - $0) } }
    // A reset passing is not proof that the provider granted new usage.
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= -60 && age < 600 && !(resetsAt.map { $0 <= now && $0 > observedAt } ?? false)
    }
    public func tone(at now: Date) -> MeterTone {
        guard isFresh(at: now), let left = leftPercent else { return .unknown }
        return MeterTone(left: left, pace: pace(at: now)?.pace)
    }
}

public struct SubscriptionAccount: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var provider: Provider
    public var label: String
    public var plan: String?
    public var disabled: Bool
    public var unavailable: Bool
    public var cooldownUntil: Date?
    public var windows: [QuotaWindow]
    public var checkedAt: Date?
    public var readError: String?
    public var extraUsageEnabled: Bool?
    public var paidCredits: Double?
    public var unlimitedCredits: Bool
    public var resetGrantsLeft: Int?

    public init(id: String, provider: Provider, label: String, plan: String? = nil,
                disabled: Bool = false, unavailable: Bool = false, cooldownUntil: Date? = nil,
                windows: [QuotaWindow] = [], checkedAt: Date? = nil, readError: String? = nil,
                extraUsageEnabled: Bool? = nil, paidCredits: Double? = nil,
                unlimitedCredits: Bool = false, resetGrantsLeft: Int? = nil) {
        self.id = id; self.provider = provider; self.label = label; self.plan = plan
        self.disabled = disabled; self.unavailable = unavailable; self.cooldownUntil = cooldownUntil
        self.windows = windows; self.checkedAt = checkedAt; self.readError = readError
        self.extraUsageEnabled = extraUsageEnabled; self.paidCredits = paidCredits
        self.unlimitedCredits = unlimitedCredits; self.resetGrantsLeft = resetGrantsLeft
    }
    public var claudeRowWindows: [QuotaWindow?] {
        [windows.first { $0.id == "five_hour" }, windows.first { $0.id == "seven_day" }]
    }
    public var tightestWindow: QuotaWindow? {
        windows.filter { !$0.modelScoped && $0.leftPercent != nil }
            .min { ($0.leftPercent ?? 100) < ($1.leftPercent ?? 100) }
    }
    /// What the tighter shared allowance leaves, from a current reading. A disabled account still has one.
    public func freshLeft(at now: Date) -> Double? {
        let shared = windows.filter { !$0.modelScoped }
        guard readError == nil, !shared.isEmpty,
              shared.allSatisfy({ $0.isFresh(at: now) && $0.leftPercent != nil }) else { return nil }
        return shared.compactMap(\.leftPercent).min()
    }
    /// The pace of the shared allowances together.
    public func pace(at now: Date) -> Pace? { Pace.combined(windows.filter { !$0.modelScoped }, at: now) }
    public func tone(at now: Date) -> MeterTone {
        guard let left = freshLeft(at: now) else { return .unknown }
        return MeterTone(left: left, pace: pace(at: now))
    }
    public func isReady(at now: Date) -> Bool {
        guard !disabled, !unavailable, let left = freshLeft(at: now), left > 0 else { return false }
        return cooldownUntil.map { $0 <= now } ?? true
    }
}

public struct QuotaSnapshot: Codable, Sendable {
    public var accounts: [SubscriptionAccount]
    public var fetchedAt: Date
    public init(accounts: [SubscriptionAccount], fetchedAt: Date = Date()) {
        self.accounts = accounts; self.fetchedAt = fetchedAt
    }
}
