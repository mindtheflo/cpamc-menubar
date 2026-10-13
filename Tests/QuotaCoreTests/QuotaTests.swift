import XCTest
@testable import QuotaCore

final class QuotaTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func json(_ value: String) throws -> JSONValue { try .decode(Data(value.utf8)) }
    func window(_ used: Double?, reset: Date? = nil, scoped: Bool = false) -> QuotaWindow {
        .init(id: scoped ? "seven_day_opus" : "seven_day", usedPercent: used,
              resetsAt: reset ?? now.addingTimeInterval(3600), observedAt: now, modelScoped: scoped)
    }
    func account(_ id: String, used: Double?, disabled: Bool = false) -> SubscriptionAccount {
        .init(id: id, provider: .claude, label: id, disabled: disabled, windows: [window(used)], checkedAt: now)
    }
    func testWeeklyExhaustionBlocksEvenWithFreshFiveHourAllowance() throws {
        let usage = try json("""
        {"five_hour":{"utilization":37,"resets_at":null},"seven_day":{"utilization":100,"resets_at":null},"extra_usage":{"is_enabled":false}}
        """)
        let a = QuotaParser.applyClaude(usage, profile: nil, to: account("a", used: 0), at: now)
        XCTAssertEqual(a.freshLeft(at: now), 0)
        XCTAssertEqual(a.tone(at: now), .out)
        XCTAssertEqual(a.tightestWindow?.id, "seven_day")
        XCTAssertFalse(a.isReady(at: now))
        XCTAssertEqual(a.extraUsageEnabled, false)
    }
    func testProviderUsesBestAccountAndDoesNotAddPercentages() {
        let snapshot = QuotaSnapshot(accounts: [account("one", used: 31), account("two", used: 4)])
        let summary = snapshot.summary(.claude, at: now)
        XCTAssertEqual(summary.leftPercent, 96)
        XCTAssertEqual(summary.readyCount, 2)
    }
    func testDisabledAccountCannotMakeExhaustedPoolLookAvailable() {
        let snapshot = QuotaSnapshot(accounts: [account("enabled", used: 100), account("disabled", used: 0, disabled: true)])
        XCTAssertEqual(snapshot.summary(.claude, at: now).leftPercent, 0)
        XCTAssertEqual(snapshot.summary(.claude, at: now).accountCount, 1)
        XCTAssertEqual(snapshot.summary(.claude, at: now).tone, .out)
    }
    func testUnknownAccountPreventsClaimingWholeProviderIsExhausted() {
        let snapshot = QuotaSnapshot(accounts: [account("out", used: 100), account("unknown", used: nil)])
        XCTAssertEqual(snapshot.summary(.claude, at: now).tone, .unknown)
        XCTAssertNil(snapshot.summary(.claude, at: now).leftPercent)
    }
    func testResetPassingDoesNotFabricateNewQuota() {
        let a = account("a", used: 100)
        let afterReset = now.addingTimeInterval(3601)
        XCTAssertNil(a.freshLeft(at: afterReset))
        XCTAssertEqual(a.windows.first?.leftPercent, 0)
        XCTAssertEqual(a.tone(at: afterReset), .unknown)
    }
    func testStaleReadIsPreservedButNotClaimedAsCurrent() {
        let a = account("a", used: 30)
        XCTAssertNil(a.freshLeft(at: now.addingTimeInterval(600)))
        XCTAssertEqual(a.tightestWindow?.leftPercent, 70)
    }
    func testCooldownDoesNotEraseQuotaButPreventsReadyState() {
        var a = account("a", used: 50)
        a.cooldownUntil = now.addingTimeInterval(120)
        a.unavailable = true
        XCTAssertEqual(a.freshLeft(at: now), 50)
        XCTAssertFalse(a.isReady(at: now))
        XCTAssertEqual(QuotaSnapshot(accounts: [a]).summary(.claude, at: now).nextReset, a.cooldownUntil)
    }
    func testModelScopedExhaustionIsNotSharedSubscriptionExhaustion() {
        var a = account("a", used: 30)
        a.windows.append(window(100, scoped: true))
        XCTAssertEqual(a.freshLeft(at: now), 70)
        XCTAssertEqual(a.tone(at: now), .ok)
    }
    func testCodexWeeklyPrimaryWindowIsNotMislabeledFiveHour() throws {
        let usage = try json("""
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":31,"limit_window_seconds":604800,"reset_at":1800604800},"secondary_window":null},"credits":{"balance":"0","unlimited":false}}
        """)
        let a = QuotaParser.applyCodex(usage, to: .init(id: "a", provider: .codex, label: "Codex"), at: now)
        XCTAssertEqual(a.windows.count, 1)
        XCTAssertEqual(a.windows.first?.id, "seven_day")
        XCTAssertEqual(a.freshLeft(at: now), 69)
        XCTAssertEqual(a.paidCredits, 0)
        XCTAssertEqual(a.plan, "Pro")
    }
    func testMissingOrInvalidUsageIsNot100PercentRemaining() throws {
        let usage = try json("""
        {"five_hour":{"utilization":null},"seven_day":{"utilization":100}}
        """)
        let a = QuotaParser.applyClaude(usage, profile: nil, to: account("a", used: 0), at: now)
        XCTAssertNil(a.freshLeft(at: now))
        XCTAssertNil(window(.nan).leftPercent)
        XCTAssertNil(window(-1).leftPercent)
        XCTAssertEqual(window(101).leftPercent, 0)
    }
    func testNewerReceiptReplacesProviderReadingWithoutOverwritingOtherWindows() throws {
        var old = account("a", used: 99)
        old.checkedAt = now.addingTimeInterval(-60)
        old.windows.append(window(25, scoped: true))
        let record: JSONValue = .object([
            "provider": .string("claude"), "auth_index": .string("a"), "email": .string("example@example.invalid"),
            "quota": .object(["observed_at": .string(ISO8601DateFormatter().string(from: now)), "signals": .object([
                "Anthropic-Ratelimit-Unified-7d-Utilization": .string("1.0"),
                "Anthropic-Ratelimit-Unified-5h-Utilization": .string("0.37"),
            ])]),
        ])
        let a = try XCTUnwrap(QuotaParser.record(record, previous: old))
        XCTAssertEqual(a.freshLeft(at: now), 0)
        XCTAssertEqual(a.windows.first { $0.modelScoped }?.usedPercent, 25)
    }
    func testLoopbackOnlyAndNoCredentialInEndpoint() {
        for valid in ["http://127.0.0.1:8317", "http://localhost:8317/", "http://[::1]:8317"] {
            XCTAssertNoThrow(try Configuration(proxyURL: valid).validatedURL())
        }
        for bad in ["https://example.com", "http://127.0.0.1.example.com", "http://key@localhost:8317", "file:///tmp/key", "http://localhost:8317/?key=x", "http://localhost:8317/api"] {
            XCTAssertThrowsError(try Configuration(proxyURL: bad).validatedURL())
        }
    }
    func testDateParsingAcceptsProviderMicrosecondsAndProxyOffsets() {
        XCTAssertNotNil(parseDate("2026-10-13T10:59:59.817877+00:00"))
        XCTAssertNotNil(parseDate("2026-10-13T13:00:25.001037+02:00"))
        XCTAssertNil(parseDate("not-a-date"))
    }
    func testAccountIDComesFromDecodedClaimsNotAnEmail() throws {
        let record = try json("""
        {"email":"example@example.invalid","id_token":{"https://api.openai.com/auth":{"chatgpt_account_id":"sample-account-id"}}}
        """)
        XCTAssertEqual(QuotaParser.chatGPTAccountID(record), "sample-account-id")
    }
    func testPromoGrantIsReadOnlyCountAndPlanLabelIsRecognized() throws {
        let usage = try json("""
        {"seven_day":{"utilization":100},"cedar_ember":{"eligible":true,"grants":[{"resets_left":1}]}}
        """)
        let profile = try json("""
        {"organization":{"rate_limit_tier":"default_claude_max_20x"}}
        """)
        let a = QuotaParser.applyClaude(usage, profile: profile, to: account("a", used: 100), at: now)
        XCTAssertEqual(a.resetGrantsLeft, 1)
        XCTAssertEqual(a.plan, "Max 20×")
    }

    func testDisabledUsageCanBeInspectedWithoutMakingItRoutable() {
        var a = SubscriptionAccount(id: "off", provider: .claude, label: "Off", disabled: true)
        XCTAssertFalse(a.canInspect)
        a.windows = [window(20)]
        XCTAssertTrue(a.canInspect)
        XCTAssertFalse(a.isReady(at: now))
        XCTAssertNil(a.freshLeft(at: now))
    }
    func testClaudeRowAlwaysOrdersSessionBeforeWeeklyAndDoesNotSubstituteModelQuota() {
        var a = account("a", used: 71)
        a.windows.append(.init(id: "seven_day_opus", usedPercent: 5, observedAt: now, modelScoped: true))
        XCTAssertNil(a.claudeRowWindows[0])
        XCTAssertEqual(a.claudeRowWindows[1]?.usedPercent, 71)
        a.windows.append(.init(id: "five_hour", usedPercent: 20, observedAt: now))
        XCTAssertEqual(a.claudeRowWindows.compactMap { $0?.id }, ["five_hour", "seven_day"])
        XCTAssertEqual(a.claudeRowWindows[0]?.leftPercent, 80)
    }
    func testServiceControlRejectsUnrelatedExecutableConfigAndPort() throws {
        let root = URL(fileURLWithPath: "/tmp/proxy-fixture")
        let plistURL = URL(fileURLWithPath: "/tmp/service.plist")
        func definition(executable: String = "/tmp/proxy-fixture/bin/CLIProxyAPI", config: String = "/tmp/proxy-fixture/config.yaml", port: Int = 8317) throws -> ProxyServiceDefinition {
            let data = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.flo.cliproxyapi", "ProgramArguments": [executable, "-config", config]], format: .xml, options: 0)
            return try .init(plistURL: plistURL, data: data, expectedRoot: root, expectedPort: port, configText: "server:\n  port: 8317\n", uid: 501)
        }
        XCTAssertEqual(try definition().target, "gui/501/com.flo.cliproxyapi")
        XCTAssertThrowsError(try definition(executable: "/bin/sh"))
        XCTAssertThrowsError(try definition(config: "/tmp/other/config.yaml"))
        XCTAssertThrowsError(try definition(port: 9000))
    }
}
