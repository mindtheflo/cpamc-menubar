import AppKit
import SwiftUI
import QuotaCore

@MainActor
final class QuotaStore: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var busy = false
    @Published var error: String?
    @Published var accountUpdating: String?
    @Published var accountUpdateError: String?
    @Published var now = Date()
    @Published var configuration: Configuration
    @Published var iconPreferences = IconPreferences.load() {
        didSet { iconPreferences.save() }
    }
    var iconMetrics: [IconMetric] {
        IconMetrics.bars(snapshot: snapshot, preferences: iconPreferences, at: now, offline: error != nil)
    }
    var iconDescription: String {
        return iconMetrics.map { metric in
            let value: String
            if metric.capacity == 200, let left = metric.leftPercent {
                let amount = "\(Int(left.rounded()))/200% " + Copy.text("combinedLeft")
                if metric.isPartial {
                    let missing = metric.missingProviders.map { $0 == .codex ? "OpenAI" : "Claude" }.joined(separator: " + ")
                    value = "≥" + amount + " (" + missing + " " + Copy.text("notReported") + ")"
                } else { value = amount }
            } else { value = Copy.percent(metric.leftPercent) }
            return Copy.text(metric.label) + ": " + value
        }.joined(separator: " · ")
    }
    let demo: Bool
    private var client: ProxyClient
    private var loop: Task<Void, Never>?
    private var clock: Task<Void, Never>?

    init(demo: Bool = false) {
        self.demo = demo
        let initial = Configuration.load()
        configuration = initial
        client = ProxyClient(configuration: initial)
        if demo { snapshot = Demo.snapshot(at: now) }
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }
    func refresh(force: Bool = false) async {
        guard !busy else { return }
        now = Date()
        if demo { return }
        busy = true
        defer { busy = false }
        do {
            snapshot = try await client.fetch(previous: snapshot, force: force)
            error = nil
        } catch {
            self.error = (error as? ProxyError)?.localizedDescription ?? ProxyError.unavailable.localizedDescription
        }
    }
    func setAccountEnabled(_ account: SubscriptionAccount, enabled: Bool) async {
        guard !busy, accountUpdating == nil else { return }
        busy = true; accountUpdating = account.id; accountUpdateError = nil
        defer { busy = false; accountUpdating = nil }
        do {
            let updated: SubscriptionAccount
            if demo {
                var preview = account; preview.disabled = !enabled; updated = preview
            } else {
                updated = try await client.setAccountEnabled(account, enabled: enabled)
            }
            if let index = snapshot?.accounts.firstIndex(where: { $0.id == account.id }) {
                snapshot?.accounts[index] = updated
            }
        } catch {
            accountUpdateError = Copy.text("accountUpdateFailed")
            // Recover the current display from a read, without replaying the mutation.
            if !demo, let current = try? await client.fetch(previous: snapshot) { snapshot = current }
        }
    }
    func configure(_ new: Configuration) throws {
        guard !busy else { return }
        try new.save()
        configuration = new
        client = ProxyClient(configuration: new)
        snapshot = nil
        error = nil
        Task { await refresh(force: true) }
    }
    func openDashboard() {
        if let url = configuration.dashboardURL { NSWorkspace.shared.open(url) }
    }
    var summaries: [ProviderSummary] {
        guard let snapshot else { return [] }
        return Provider.allCases.compactMap { provider in
            let summary = snapshot.summary(provider, at: now)
            return summary.accountCount > 0 ? summary : nil
        }
    }
}
