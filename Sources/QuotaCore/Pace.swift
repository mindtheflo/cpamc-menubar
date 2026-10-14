import Foundation

/// How fast an allowance is being used, compared with what it allows until its renewal.
public enum Pace: String, Codable, Sendable {
    /// At this pace, it runs out before it renews.
    case over
    case steady
    /// At this pace, less than half of it is used by the renewal.
    case under

    /// Until about a quarter of the window has passed, the estimate leans on a moderate pace, three quarters of the
    /// allowance per window, so that one early burst or a quiet start doesn't decide it.
    static let priorWeight = 0.25, priorRate = 0.75

    /// Allowances drawn on together: one on pace to run out decides, and they are well under only if all are.
    /// An unused allowance whose pace can't be told doesn't count; one in use leaves the pace unknown.
    public static func combined(_ windows: [QuotaWindow], at now: Date) -> Pace? {
        var paces: [Pace] = []
        for window in windows {
            if let estimate = window.pace(at: now) { paces.append(estimate.pace) }
            else if window.usedPercent != 0 { return nil }
        }
        guard !paces.isEmpty else { return nil }
        return paces.contains(.over) ? .over : paces.allSatisfy { $0 == .under } ? .under : .steady
    }
}

public struct PaceEstimate: Sendable, Equatable {
    public let pace: Pace
    /// Percent of the allowance used by the renewal at this pace; above 100, it runs out first.
    public let projectedUse: Double
    /// When it runs out at this pace, if that comes before the renewal.
    public let runsOutAt: Date?
}

extension QuotaWindow {
    /// The window's length, known from its id: a session lasts five hours, a weekly allowance seven days.
    public var duration: TimeInterval? {
        id == "five_hour" ? 5 * 3600 : id.hasPrefix("seven_day") ? 7 * 86400 : nil
    }

    /// The average rate since the window started, carried on to the renewal.
    public func pace(at now: Date) -> PaceEstimate? {
        guard isFresh(at: now), let used = usedPercent.map({ $0 / 100 }), let duration, let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        // A renewal much further away than one window means the window isn't the one its id names.
        guard remaining > 0, remaining <= duration * 1.25 else { return nil }
        let elapsed = max(0, 1 - remaining / duration)
        // Share of the allowance used per window length.
        let rate = (used + Pace.priorRate * Pace.priorWeight) / (elapsed + Pace.priorWeight)
        let projected = used + rate * remaining / duration
        return PaceEstimate(pace: projected > 1 ? .over : projected < 0.5 ? .under : .steady,
                            projectedUse: projected * 100,
                            runsOutAt: projected > 1 ? now.addingTimeInterval((1 - used) / rate * duration) : nil)
    }
}
