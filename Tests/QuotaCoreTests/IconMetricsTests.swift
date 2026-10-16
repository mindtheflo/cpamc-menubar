import XCTest
@testable import QuotaCore

final class IconMetricsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func account(_ id: String, provider: Provider = .claude, session: Double? = nil, weekly: Double, disabled: Bool = false, unavailable: Bool = false) -> SubscriptionAccount {
        var windows = [QuotaWindow(id: "seven_day", usedPercent: 100-weekly, observedAt: now)]
        if let session { windows.append(.init(id: "five_hour", usedPercent: 100-session, observedAt: now)) }
        return .init(id: id, provider: provider, label: id, disabled: disabled, unavailable: unavailable, windows: windows)
    }
    func testProviderBarsPoolWeeklyCapacityRegardlessOfTighterSessionLimits() {
        let snapshot = QuotaSnapshot(accounts: [account("c1", session:90, weekly:10), account("c2", session:20, weekly:70), account("o",provider:.codex,session:85,weekly:40)])
        let bars = IconMetrics.bars(snapshot:snapshot,preferences:.init(),at:now)
        XCTAssertEqual(bars.map(\.label),["openai","claude"])
        XCTAssertEqual(bars.map(\.leftPercent),[40,40])
        XCTAssertEqual(bars.map(\.isPartial),[false,false])
    }
    func testProviderWeeklyBarIgnoresExhaustedOrStaleSessions() {
        var a = account("a", session: 0, weekly: 86)
        a.windows[1].observedAt = now.addingTimeInterval(-601)
        let snapshot = QuotaSnapshot(accounts: [a, account("b", session: 100, weekly: 0),
            account("c", session: 100, weekly: 0), account("d", session: 100, weekly: 0),
            account("e", session: 100, weekly: 0)])
        let bar = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now)[1]
        XCTAssertEqual(bar.leftPercent!, 86.0 / 5, accuracy: 0.001)
        XCTAssertEqual(bar.missing, 0)
        XCTAssertEqual(bar.tone, .unknown) // No forecast confidence is invented from the new fill.
    }
    func testProviderWeeklyBarKeepsMissingWeeklyReadingsPartialAndExcludesNonWeeklyPlans() {
        var stale = account("stale", weekly: 100)
        stale.windows[0].observedAt = now.addingTimeInterval(-601)
        let unknown = SubscriptionAccount(id: "unknown", provider: .claude, label: "unknown")
        let monthly = SubscriptionAccount(id: "monthly", provider: .claude, label: "monthly",
            windows: [.init(id: "primary", usedPercent: 0, observedAt: now)])
        let snapshot = QuotaSnapshot(accounts: [account("a", session: 0, weekly: 86), stale, unknown, monthly,
            account("disabled", weekly: 100, disabled: true)])
        let bar = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now)[1]
        XCTAssertEqual(bar.leftPercent!, 86.0 / 3, accuracy: 0.001)
        XCTAssertEqual(bar.missing, 2)
        XCTAssertEqual(bar.tone, .unknown)
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
            pressureRange: 0.1...0.2, observedHours: 10, recentObservedHours: 2, windowPaces: ["seven_day": .under], baselineDemand: [:], recentDemand: [:])
        let trained = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now, forecasts: [.claude: estimate])
        XCTAssertEqual(trained[1].tone, .underPace)
        let partial = QuotaSnapshot(accounts: snapshot.accounts + [.init(id: "missing", provider: .claude, label: "missing")])
        XCTAssertEqual(IconMetrics.bars(snapshot: partial, preferences: .init(), at: now, forecasts: [.claude: estimate])[1].tone, .unknown)
    }
    func testTentativeForecastUsesItsHueWithLowerSaturationButNeverColoursMissingData() {
        let snapshot = QuotaSnapshot(accounts: [account("a", weekly: 50)])
        var estimate = PaceForecast.unknown(.uncertainty, at: now)
        estimate.prediction = .init(pace: .under, agreement: 0.4)
        let tentative = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now, forecasts: [.claude: estimate])[1]
        XCTAssertEqual(tentative.tone, .underPace)
        XCTAssertGreaterThan(tentative.saturation, 0)
        XCTAssertLessThan(tentative.saturation, 1)
        estimate.prediction = .init(pace: .under, agreement: 1)
        let strong = IconMetrics.bars(snapshot: snapshot, preferences: .init(), at: now, forecasts: [.claude: estimate])[1]
        XCTAssertEqual(strong.saturation, 1)
        XCTAssertEqual(strong.leftPercent, tentative.leftPercent)
        let unread = SubscriptionAccount(id: "missing", provider: .claude, label: "missing")
        let partial = IconMetrics.bars(snapshot: .init(accounts: snapshot.accounts + [unread]), preferences: .init(), at: now, forecasts: [.claude: estimate])[1]
        XCTAssertEqual(partial.tone, .unknown)
        XCTAssertEqual(partial.saturation, 0)
        let exhausted = IconMetrics.bars(snapshot: .init(accounts: [account("empty", weekly: 0)]), preferences: .init(), at: now, forecasts: [.claude: estimate])[1]
        XCTAssertEqual(exhausted.tone, .out)
        XCTAssertEqual(exhausted.saturation, 1)
    }
    func testWindowColoursKeepIndependentProviderBottlenecks() {
        let snapshot = QuotaSnapshot(accounts: [account("a", session: 40, weekly: 50), account("b", provider: .codex, session: 80, weekly: 90)])
        func estimate(_ pace: Pace) -> PaceForecast {
            .init(pace: pace, gap: nil, horizon: now, shortageAt: nil, pressureRange: 0.1...0.2,
                  observedHours: 10, recentObservedHours: 2, windowPaces: ["five_hour": pace, "seven_day": .under], baselineDemand: [:], recentDemand: [:])
        }
        var prefs = IconPreferences(); prefs.content = .windows
        let bars = IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: estimate(.under), .codex: estimate(.over)])
        XCTAssertEqual(bars.map(\.tone), [.overPace, .underPace])
        XCTAssertEqual(IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: estimate(.under)]).map(\.tone), [.unknown, .unknown])
    }
    func testWindowPredictionsKeepTheWeakestAgreementAndProviderBottleneck() {
        let snapshot = QuotaSnapshot(accounts: [account("a", weekly: 50), account("b", provider: .codex, weekly: 90)])
        var claude = PaceForecast.unknown(.uncertainty, at: now)
        claude.windowPredictions = ["seven_day": .init(pace: .under, agreement: 0.8)]
        var codex = PaceForecast.unknown(.uncertainty, at: now)
        codex.windowPredictions = ["seven_day": .init(pace: .over, agreement: 0.4)]
        var prefs = IconPreferences(); prefs.content = .windows
        let bar = IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: claude, .codex: codex])[1]
        XCTAssertEqual(bar.tone, .overPace)
        XCTAssertEqual(bar.agreement, 0.4)
        XCTAssertLessThan(bar.saturation, 1)
        XCTAssertEqual(IconMetrics.bars(snapshot: snapshot, preferences: prefs, at: now, forecasts: [.claude: claude])[1].tone, .unknown)
    }
    func testIconPreferencesPersistAndRemovedOptionsDoNotResetContent() {
        let suite = "cpamc-icon-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        var preferences = IconPreferences(); preferences.content = .windows
        preferences.save(to:defaults)
        XCTAssertEqual(IconPreferences.load(from:defaults),preferences)
        // Legacy appearance and orientation values must not discard the content choice.
        defaults.set(Data(#"{"orientation":"horizontal","appearance":"monochrome","content":"windows"}"#.utf8), forKey: IconPreferences.defaultsKey)
        XCTAssertEqual(IconPreferences.load(from: defaults), preferences)
        defaults.set(Data("invalid".utf8),forKey:IconPreferences.defaultsKey)
        XCTAssertEqual(IconPreferences.load(from:defaults),IconPreferences())
    }
}
