import Foundation

public enum IconOrientation: String, Codable, CaseIterable, Sendable { case vertical, horizontal }
public enum IconAppearance: String, Codable, CaseIterable, Sendable { case color, monochrome }
public enum IconContent: String, Codable, CaseIterable, Sendable { case providers, windows }

public struct IconPreferences: Codable, Equatable, Sendable {
    public var orientation: IconOrientation = .vertical
    public var appearance: IconAppearance = .color
    public var content: IconContent = .providers
    public init() {}
    public static let defaultsKey = "menuBarIconPreferences"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

public struct IconMetric: Sendable, Equatable {
    public let label: String
    public let leftPercent: Double?
    public let capacity: Double
    public var normalizedPercent: Double? { leftPercent.map { $0 / capacity * 100 } }
    public var tone: MeterTone {
        guard let leftPercent = normalizedPercent else { return .unknown }
        return leftPercent <= 0 ? .out : leftPercent <= 10 ? .low : .ok
    }
    public init(label: String, leftPercent: Double?, capacity: Double = 100) {
        self.label = label; self.leftPercent = leftPercent; self.capacity = capacity
    }
}

public enum IconMetrics {
    public static func bars(snapshot: QuotaSnapshot?, preferences: IconPreferences, at now: Date, offline: Bool = false) -> [IconMetric] {
        let snapshot = offline ? nil : snapshot
        switch preferences.content {
        case .providers:
            return Provider.allCases.map { provider in
                let account = bestAccount(snapshot, provider: provider, at: now)
                return IconMetric(label: provider == .codex ? "openai" : "claude", leftPercent: account?.freshLeft(at: now))
            }
        case .windows:
            // Pick one account per provider, then sum equally weighted provider allowances.
            // Keep each provider's session and weekly values tied to that same account.
            let accounts = Provider.allCases.map { bestAccount(snapshot, provider: $0, at: now) }
            return ["five_hour", "seven_day"].map { id in
                let readings = accounts.map { account -> Double? in
                    guard let window = account?.windows.first(where: { $0.id == id && !$0.modelScoped }),
                          window.isFresh(at: now) else { return nil }
                    return window.leftPercent
                }
                let total = readings.allSatisfy { $0 != nil } ? readings.compactMap { $0 }.reduce(0, +) : nil
                return IconMetric(label: id == "five_hour" ? "session" : "weekly", leftPercent: total, capacity: 200)
            }
        }
    }
    private static func bestAccount(_ snapshot: QuotaSnapshot?, provider: Provider, at now: Date) -> SubscriptionAccount? {
        let known = (snapshot?.accounts ?? []).filter { $0.provider == provider && !$0.disabled && $0.freshLeft(at: now) != nil }
        let ready = known.filter { $0.isReady(at: now) }
        // If none are ready, a confirmed exhausted allowance is still useful. Do not advertise paused positive quota.
        let candidates = ready.isEmpty ? known.filter { $0.freshLeft(at: now) == 0 } : ready
        return candidates.sorted {
            let a = $0.freshLeft(at: now) ?? -1, b = $1.freshLeft(at: now) ?? -1
            return a == b ? $0.id < $1.id : a > b
        }.first
    }
}
