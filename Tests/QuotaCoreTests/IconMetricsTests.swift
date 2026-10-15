import XCTest
@testable import QuotaCore

final class IconMetricsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func account(_ id: String, provider: Provider = .claude, session: Double? = nil, weekly: Double, disabled: Bool = false, unavailable: Bool = false) -> SubscriptionAccount {
        var windows = [QuotaWindow(id: "seven_day", usedPercent: 100-weekly, observedAt: now)]
        if let session { windows.append(.init(id: "five_hour", usedPercent: 100-session, observedAt: now)) }
        return .init(id: id, provider: provider, label: id, disabled: disabled, unavailable: unavailable, windows: windows)
    }
    func testProviderBarsPoolEachProvidersEnabledAccountsByTheirTighterLimit() {
        let snapshot = QuotaSnapshot(accounts: [account("c1", session:90, weekly:10), account("c2", session:20, weekly:70), account("o",provider:.codex,session:85,weekly:40)])
        let bars = IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now)
        XCTAssertEqual(bars.map(\.label),["openai","claude"])
        XCTAssertEqual(bars.map(\.leftPercent),[40,15])
        XCTAssertEqual(bars.map(\.isPartial),[false,false])
    }
    func testWindowBarsPoolEveryEnabledAccountOutOf100Percent() throws {
        let snapshot = QuotaSnapshot(accounts:[account("a",session:90,weekly:10), account("b",session:20,weekly:70), account("o",provider:.codex,session:80,weekly:60)])
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot:snapshot,preferences:prefs,at:now)
        XCTAssertEqual(bars.map(\.label),["session","weekly"])
        XCTAssertEqual(try XCTUnwrap(bars[0].leftPercent),190.0/3,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(bars[1].leftPercent),140.0/3,accuracy:0.001)
        XCTAssertEqual(bars.map(\.isPartial),[false,false])
    }
    func testAPlanWithoutASessionAddsNothingToIt() {
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot:.init(accounts:[account("o",provider:.codex,weekly:55), account("c",session:60,weekly:25)]),preferences:prefs,at:now)
        XCTAssertEqual(bars[0].leftPercent,60)
        XCTAssertFalse(bars[0].isPartial)
        XCTAssertEqual(bars[1].leftPercent,40)
        XCTAssertFalse(bars[1].isPartial)
    }
    func testAnAccountWithoutAReadingCountsAsEmptyAndMarksTheTotalAsAMinimum() {
        var prefs = IconPreferences(); prefs.content = .windows
        let unread = SubscriptionAccount(id:"unread", provider:.codex, label:"unread")
        let bars = IconMetrics.bars(snapshot:.init(accounts:[unread, account("c",session:60,weekly:20)]),preferences:prefs,at:now)
        XCTAssertEqual(bars.map(\.leftPercent),[30,10])
        XCTAssertEqual(bars.map(\.missing),[1,1])
        XCTAssertEqual(IconMetrics.bars(snapshot:.init(accounts:[unread]),preferences:.init(),at:now)[0].leftPercent,nil)
    }
    func testPartialZeroDoesNotClaimEveryAccountIsExhausted() {
        var prefs = IconPreferences(); prefs.content = .windows
        let unread = SubscriptionAccount(id:"unread", provider:.claude, label:"unread")
        let bars = IconMetrics.bars(snapshot:.init(accounts:[account("c",session:0,weekly:0), unread]),preferences:prefs,at:now)
        XCTAssertEqual(bars[0].leftPercent,0)
        XCTAssertTrue(bars[0].isPartial)
        XCTAssertEqual(bars[0].tone,.unknown)
        let empty = IconMetrics.bars(snapshot:nil,preferences:prefs,at:now)
        XCTAssertNil(empty[0].leftPercent)
        XCTAssertEqual(empty[0].tone,.unknown)
    }
    func testDisabledAccountsAreLeftOutAndStaleOnesAreNotGuessed() throws {
        var stale = account("stale",session:100,weekly:100)
        stale.windows = stale.windows.map { var w = $0; w.observedAt = now.addingTimeInterval(-601); return w }
        let snapshot = QuotaSnapshot(accounts:[account("disabled",session:100,weekly:100,disabled:true),account("paused",session:100,weekly:100,unavailable:true),stale,account("active",session:50,weekly:30)])
        let claude = IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now)[1]
        // The paused account is still enabled, so its allowance counts; the stale one counts as empty.
        XCTAssertEqual(try XCTUnwrap(claude.leftPercent),130.0/3,accuracy:0.001)
        XCTAssertEqual(claude.missing,1)
        XCTAssertEqual(IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now,offline:true).map(\.leftPercent),[nil,nil])
    }
    func testExhaustionAndNoAccountRemainDistinct() {
        let bars = IconMetrics.bars(snapshot:.init(accounts:[account("empty",weekly:0,unavailable:true)]),preferences:.init(),at:now)
        XCTAssertEqual(bars[0].tone,.unknown)
        XCTAssertEqual(bars[1].tone,.out)
        XCTAssertEqual(bars[1].leftPercent,0)
    }
    func testGlobalForecastColoursNeverFallbackToQuotaLevels() {
        let snapshot = QuotaSnapshot(accounts: [account("a", weekly: 5)])
        let untrained = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now)
        XCTAssertEqual(untrained[1].tone, .unknown)
        let estimate = PaceForecast(pace: .under, gap: nil, horizon: now, shortageAt: nil,
            pressureRange: 0.1...0.2, observedHours: 10, windowPaces: ["seven_day": .under], baselineDemand: [:], recentDemand: [:])
        let trained = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now, forecasts: [.claude: estimate])
        XCTAssertEqual(trained[1].tone, .underPace)
        let partial = QuotaSnapshot(accounts: snapshot.accounts + [.init(id: "missing", provider: .claude, label: "missing")])
        XCTAssertEqual(IconMetrics.bars(snapshot: partial, preferences: .init(), at: now, forecasts: [.claude: estimate])[1].tone, .unknown)
    }
    func testWindowColoursKeepIndependentProviderBottlenecks() {
        let snapshot = QuotaSnapshot(accounts: [account("a", session: 40, weekly: 50), account("b", provider: .codex, session: 80, weekly: 90)])
        func estimate(_ pace: Pace) -> PaceForecast {
            .init(pace: pace, gap: nil, horizon: now, shortageAt: nil, pressureRange: 0.1...0.2,
                  observedHours: 10, windowPaces: ["five_hour": pace, "seven_day": .under], baselineDemand: [:], recentDemand: [:])
        }
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: estimate(.under), .codex: estimate(.over)])
        XCTAssertEqual(bars.map(\.tone), [.overPace, .underPace])
        XCTAssertEqual(IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: estimate(.under)]).map(\.tone), [.unknown, .unknown])
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
