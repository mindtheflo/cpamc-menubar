import Foundation
import ServiceManagement
import QuotaCore

@MainActor
final class DesktopControls: ObservableObject {
    @Published var loginEnabled = false
    @Published var loginApprovalRequired = false
    @Published var serviceRegistered = false
    @Published var serviceAvailable = false
    @Published var busy = false
    @Published var loginError: String?
    @Published var serviceError: String?
    private var service: ProxyServiceDefinition?

    func refresh(configuration: Configuration) async {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginApprovalRequired = status == .requiresApproval
        service = try? ProxyServiceDefinition.load(configuration: configuration)
        serviceAvailable = service != nil
        if let service { serviceRegistered = await ProxyService.isRegistered(service) }
        else { serviceRegistered = false }
    }
    func setLogin(_ enabled: Bool, configuration: Configuration) async {
        guard !busy else { return }
        busy = true; loginError = nil
        defer { busy = false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { loginError = Copy.text("loginError") }
        await refresh(configuration: configuration)
    }
    func control(start: Bool, store: QuotaStore) async {
        guard !busy, let service else { return }
        busy = true; serviceError = nil
        defer { busy = false }
        do {
            if start { try await ProxyService.start(service) }
            else { try await ProxyService.stop(service) }
            await refresh(configuration: store.configuration)
            await store.refresh()
        } catch { serviceError = Copy.text("serviceError") }
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
