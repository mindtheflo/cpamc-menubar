import XCTest
@testable import QuotaCore

final class PaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600, day: TimeInterval = 86400
    func window(_ id: String = "seven_day", used: Double?, renewsIn: TimeInterval?, scoped: Bool = false) -> QuotaWindow {
        .init(id: id, usedPercent: used, resetsAt: renewsIn.map { now.addingTimeInterval($0) }, observedAt: now, modelScoped: scoped)
    }
    func account(_ id: String, provider: Provider = .claude, _ windows: [QuotaWindow]) -> SubscriptionAccount {
        .init(id: id, provider: provider, label: id, windows: windows, checkedAt: now)
    }

    func testEvenSpreadIsSteady() throws {
        let estimate = try XCTUnwrap(window(used: 50, renewsIn: 3.5 * day).pace(at: now))
        XCTAssertEqual(estimate.pace, .steady)
        XCTAssertEqual(estimate.projectedUse, 95.8, accuracy: 0.1)
        XCTAssertNil(estimate.runsOutAt)
        XCTAssertEqual(window("five_hour", used: 80, renewsIn: hour).pace(at: now)?.pace, .steady)
    }
    func testFastUseRunsOutBeforeTheRenewal() throws {
        let session = window("five_hour", used: 40, renewsIn: 4 * hour)
        let estimate = try XCTUnwrap(session.pace(at: now))
        XCTAssertEqual(estimate.pace, .over)
        XCTAssertGreaterThan(estimate.projectedUse, 100)
        let runsOut = try XCTUnwrap(estimate.runsOutAt)
        XCTAssertGreaterThan(runsOut, now)
        XCTAssertLessThan(runsOut, try XCTUnwrap(session.resetsAt))
        XCTAssertEqual(session.tone(at: now), .overPace)
        XCTAssertEqual(window(used: 55, renewsIn: 3.5 * day).pace(at: now)?.pace, .over)
    }
    func testLittleUseIsWellUnder() {
        XCTAssertEqual(window(used: 15, renewsIn: 2.8 * day).pace(at: now)?.pace, .under)
        XCTAssertEqual(window("five_hour", used: 0, renewsIn: 2 * hour).pace(at: now)?.pace, .under)
        XCTAssertEqual(window(used: 15, renewsIn: 2.8 * day).tone(at: now), .underPace)
    }
    func testAQuietOrBusyStartDoesNotDecideThePace() {
        // Nothing used yet, or a burst in a window's first minutes, is not yet a pace.
        XCTAssertEqual(window("five_hour", used: 0, renewsIn: 5 * hour).pace(at: now)?.pace, .steady)
        XCTAssertEqual(window("five_hour", used: 4, renewsIn: 4.9 * hour).pace(at: now)?.pace, .steady)
        XCTAssertEqual(window(used: 2, renewsIn: 6.9 * day).pace(at: now)?.pace, .steady)
        // A heavy start still counts.
        XCTAssertEqual(window("five_hour", used: 20, renewsIn: 4.5 * hour).pace(at: now)?.pace, .over)
    }
    func testPaceNeedsAFreshReadingOfAKnownWindow() {
        XCTAssertNil(window(used: 50, renewsIn: nil).pace(at: now))
        XCTAssertNil(window("primary", used: 50, renewsIn: day).pace(at: now))
        XCTAssertNil(window("five_hour", used: 50, renewsIn: 2 * day).pace(at: now))
        XCTAssertNil(window(used: nil, renewsIn: day).pace(at: now))
        XCTAssertNil(window(used: 50, renewsIn: day).pace(at: now.addingTimeInterval(601)))
        XCTAssertNil(window(used: 50, renewsIn: 60).pace(at: now.addingTimeInterval(120)))
    }
    func testColorShowsThePaceOnceLevelAloneNoLongerDecides() {
        // Little left but renewing before it runs out: on track, not a warning.
        XCTAssertEqual(window("five_hour", used: 95, renewsIn: 10 * 60).tone(at: now), .ok)
        XCTAssertEqual(window(used: 100, renewsIn: day).tone(at: now), .out)
        // Without a pace, the level decides as before.
        XCTAssertEqual(window(used: 95, renewsIn: nil).tone(at: now), .low)
        XCTAssertEqual(window(used: 50, renewsIn: nil).tone(at: now), .ok)
    }
    func testAnAccountRunsOutIfAnyAllowanceDoesAndIsUnderOnlyIfAllAre() {
        let fastSession = window("five_hour", used: 40, renewsIn: 4 * hour)
        let quietSession = window("five_hour", used: 0, renewsIn: 2 * hour)
        let steadyWeek = window(used: 50, renewsIn: 3.5 * day)
        let quietWeek = window(used: 15, renewsIn: 2.8 * day)
        XCTAssertEqual(account("a", [fastSession, quietWeek]).pace(at: now), .over)
        XCTAssertEqual(account("a", [fastSession, quietWeek]).tone(at: now), .overPace)
        XCTAssertEqual(account("a", [quietSession, quietWeek]).tone(at: now), .underPace)
        XCTAssertEqual(account("a", [quietSession, steadyWeek]).tone(at: now), .ok)
        // A model's own allowance has its own pace, shown in the details only.
        let fastOpus = window("seven_day_opus", used: 90, renewsIn: 6 * day, scoped: true)
        XCTAssertEqual(fastOpus.pace(at: now)?.pace, .over)
        XCTAssertEqual(account("a", [quietSession, quietWeek, fastOpus]).pace(at: now), .under)
    }
    func testAnAllowanceInUseWithoutAPaceLeavesTheLevelToDecide() {
        let quietWeek = window(used: 15, renewsIn: 2.8 * day)
        // A session that hasn't started has no renewal time yet and doesn't count.
        XCTAssertEqual(account("a", [window("five_hour", used: 0, renewsIn: nil), quietWeek]).pace(at: now), .under)
        let unknown = account("a", [window("primary", used: 92, renewsIn: hour), quietWeek])
        XCTAssertNil(unknown.pace(at: now))
        XCTAssertEqual(unknown.tone(at: now), .low)
        XCTAssertNil(Pace.combined([], at: now))
    }
    func testAllowancesOfOneKindPoolTheirUse() {
        let fastWeek = window(used: 55, renewsIn: 3.5 * day)
        let quietWeek = window(used: 15, renewsIn: 2.8 * day)
        XCTAssertEqual(Pace.combined([fastWeek], at: now), .over)
        XCTAssertEqual(Pace.combined([fastWeek, quietWeek], at: now), .steady)
        XCTAssertEqual(Pace.combined([quietWeek, quietWeek], at: now), .under)
        // An unused session that hasn't started adds room but no pace of its own.
        let fastSession = window("five_hour", used: 40, renewsIn: 4 * hour)
        XCTAssertEqual(Pace.combined([fastSession, window("five_hour", used: 0, renewsIn: nil)], at: now), .steady)
        XCTAssertNil(Pace.combined([fastWeek, window(used: 30, renewsIn: nil)], at: now))
    }
    func testIconBarsCarryThePaceOfTheAccountsTheyShow() {
        let codex = account("o", provider: .codex, [window("five_hour", used: 40, renewsIn: 4 * hour), window(used: 15, renewsIn: 2.8 * day)])
        let claude = account("c", [window("five_hour", used: 0, renewsIn: 2 * hour), window(used: 15, renewsIn: 2.8 * day)])
        let snapshot = QuotaSnapshot(accounts: [codex, claude], fetchedAt: now)
        let providers = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now)
        XCTAssertEqual(providers.map(\.pace), [.over, .under])
        XCTAssertEqual(providers.map(\.tone), [.overPace, .underPace])
        var preferences = IconPreferences(); preferences.content = .windows
        // Pooled, one account's fast session is absorbed by the other's quiet one.
        let windows = IconMetrics.bars(snapshot: snapshot, preferences: preferences, at: now)
        XCTAssertEqual(windows.map(\.pace), [.steady, .under])
        XCTAssertEqual(IconMetrics.bars(snapshot: snapshot, preferences: preferences, at: now, offline: true).map(\.tone), [.unknown, .unknown])
    }
}
