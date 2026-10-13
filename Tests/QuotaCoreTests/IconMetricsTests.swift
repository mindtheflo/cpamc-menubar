import XCTest
@testable import QuotaCore

final class IconMetricsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func account(_ id: String, provider: Provider = .claude, session: Double? = nil, weekly: Double, disabled: Bool = false, unavailable: Bool = false) -> SubscriptionAccount {
        var windows = [QuotaWindow(id: "seven_day", usedPercent: 100-weekly, observedAt: now)]
        if let session { windows.append(.init(id: "five_hour", usedPercent: 100-session, observedAt: now)) }
        return .init(id: id, provider: provider, label: id, disabled: disabled, unavailable: unavailable, windows: windows)
    }
    func testProviderBarsUseTightestLimitNotLargestWindowOrSummedSubscriptions() {
        let snapshot = QuotaSnapshot(accounts: [account("c1", session:90, weekly:10), account("c2", session:20, weekly:70), account("o",provider:.codex,session:85,weekly:40)])
        let bars = IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now)
        XCTAssertEqual(bars.map(\.label),["openai","claude"])
        XCTAssertEqual(bars.map(\.leftPercent),[40,20])
    }
    func testCombinedWindowsSumProvidersUsingOneBestAccountEach() {
        let snapshot = QuotaSnapshot(accounts:[account("a",session:90,weekly:10), account("b",session:20,weekly:70), account("o",provider:.codex,session:80,weekly:60)])
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot:snapshot,preferences:prefs,at:now)
        XCTAssertEqual(bars.map(\.label),["session","weekly"])
        XCTAssertEqual(bars.map(\.leftPercent),[100,130])
        XCTAssertEqual(bars.map(\.normalizedPercent),[50,65])
        XCTAssertEqual(bars.map(\.capacity),[200,200])
    }
    func testMissingSessionIsUnknownNotInferredFromWeekly() {
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot:.init(accounts:[account("o",provider:.codex,weekly:55), account("c",session:60,weekly:25)]),preferences:prefs,at:now)
        XCTAssertNil(bars[0].leftPercent)
        XCTAssertEqual(bars[1].leftPercent,80)
    }
    func testDisabledPausedAndStaleAccountsCannotMakeIconLookAvailable() {
        var stale = account("stale",session:100,weekly:100)
        stale.windows = stale.windows.map { var w = $0; w.observedAt = now.addingTimeInterval(-601); return w }
        let snapshot = QuotaSnapshot(accounts:[account("disabled",session:100,weekly:100,disabled:true),account("paused",session:100,weekly:100,unavailable:true),stale,account("active",session:50,weekly:30)])
        XCTAssertEqual(IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now)[1].leftPercent,30)
        XCTAssertEqual(IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now,offline:true).map(\.leftPercent),[nil,nil])
    }
    func testExhaustionAndNoAccountRemainDistinct() {
        let bars = IconMetrics.bars(snapshot:.init(accounts:[account("empty",weekly:0,unavailable:true)]),preferences:.init(),at:now)
        XCTAssertEqual(bars[0].tone,.unknown)
        XCTAssertEqual(bars[1].tone,.out)
        XCTAssertEqual(bars[1].leftPercent,0)
    }
    func testIconPreferencesPersistAndCorruptionFallsBackToVertical() {
        let suite = "cpamc-icon-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        XCTAssertEqual(IconPreferences.load(from:defaults).orientation,.vertical)
        var preferences = IconPreferences(); preferences.orientation = .horizontal; preferences.appearance = .monochrome; preferences.content = .windows
        preferences.save(to:defaults)
        XCTAssertEqual(IconPreferences.load(from:defaults),preferences)
        defaults.set(Data("invalid".utf8),forKey:IconPreferences.defaultsKey)
        XCTAssertEqual(IconPreferences.load(from:defaults),IconPreferences())
    }
}
