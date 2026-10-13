import AppKit
import SwiftUI
import QuotaCore

@MainActor
final class QuotaStore: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var busy = false
    @Published var error: String?
    @Published var now = Date()
    @Published var configuration: Configuration
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
