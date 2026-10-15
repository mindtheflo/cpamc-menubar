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
    /// What the enabled accounts behind the bar have left together, out of all their allowances.
    public let leftPercent: Double?
    /// Enabled accounts without a current reading: counted as nothing left, so the bar shows at least this much.
    public let missing: Int
    /// How fast the allowances behind the bar are being used, when it can be told.
    public let pace: Pace?
    public var isPartial: Bool { missing > 0 }
    public var tone: MeterTone {
        guard let leftPercent else { return .unknown }
        if leftPercent <= 0 && isPartial { return .unknown }
        return MeterTone(left: leftPercent, pace: pace)
    }
    public init(label: String, leftPercent: Double?, missing: Int = 0, pace: Pace? = nil) {
        self.label = label; self.leftPercent = leftPercent; self.missing = missing; self.pace = pace
    }
}

public enum IconMetrics {
    /// Each bar pools the accounts enabled in the proxy: together their allowances are 100%, each account counting
    /// the same, since the proxy reports usage as a share of each plan rather than tokens or dollars.
    public static func bars(snapshot: QuotaSnapshot?, preferences: IconPreferences, at now: Date, offline: Bool = false) -> [IconMetric] {
        let enabled = (offline ? nil : snapshot)?.accounts.filter { !$0.disabled } ?? []
        switch preferences.content {
        case .providers:
            // An account can use only what its tighter allowance leaves.
            return Provider.allCases.map { provider in
                let accounts = enabled.filter { $0.provider == provider }
                let read = accounts.filter { $0.freshLeft(at: now) != nil }
                let left = read.compactMap { $0.freshLeft(at: now) }
                return IconMetric(label: provider == .codex ? "openai" : "claude",
                                  leftPercent: left.isEmpty ? nil : left.reduce(0, +) / Double(accounts.count),
                                  missing: accounts.count - read.count,
                                  pace: Pace.combined(read.flatMap { $0.windows.filter { !$0.modelScoped } }, at: now))
            }
        case .windows:
            return ["five_hour", "seven_day"].map { id in
                var windows: [QuotaWindow] = [], missing = 0
                for account in enabled {
                    let shared = account.windows.filter { !$0.modelScoped }
                    // A plan without this allowance adds nothing to it; an account not read yet may have one.
                    guard let window = shared.first(where: { $0.id == id }) else {
                        if shared.isEmpty { missing += 1 }
                        continue
                    }
                    if account.readError == nil, window.isFresh(at: now), window.leftPercent != nil { windows.append(window) }
                    else { missing += 1 }
                }
                let left = windows.compactMap(\.leftPercent)
                return IconMetric(label: id == "five_hour" ? "session" : "weekly",
                                  leftPercent: left.isEmpty ? nil : left.reduce(0, +) / Double(left.count + missing),
                                  missing: missing, pace: Pace.combined(windows, at: now))
            }
        }
    }
}
