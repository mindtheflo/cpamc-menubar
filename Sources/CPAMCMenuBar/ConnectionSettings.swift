import AppKit
import SwiftUI
import QuotaCore

struct ConnectionSettings: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var updater: Updater
    let back: () -> Void
    @State private var endpoint = ""
    @State private var keyFile = ""
    @State private var error: String?
    @State private var testing = false
    @State private var testPassed: Bool?
    @State private var contentHeight: CGFloat = 0
    @StateObject private var controls = DesktopControls()
    @AppStorage("hideAccountNames") private var hideNames = false
    @AppStorage("language") private var language = "auto"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(Copy.text("settingsTitle")).fontWeight(.medium)
                    Spacer()
                }.frame(height: 29).padding(.horizontal, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Copy.text("back"))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    IconSettings(store: store).id(language)
                    general
                    proxy
                    connection
                    updates
                }
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }.frame(height: min(contentHeight, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
        }
        .onChange(of: endpoint) { _ in testPassed = nil }
        .onChange(of: keyFile) { _ in testPassed = nil }
        .task { await controls.refresh(configuration: store.configuration) }.onAppear { endpoint = store.configuration.proxyURL; keyFile = store.configuration.managementKeyFile }
    }
    private var general: some View {
        SettingsSection(Copy.text("general")) {
            SettingRow(Copy.text("launchAtLogin")) {
                Toggle(Copy.text("launchAtLogin"), isOn: Binding(get: { controls.loginEnabled }, set: { value in
                    Task { await controls.setLogin(value, configuration: store.configuration) }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(controls.busy)
            }
            if controls.loginApprovalRequired {
                Button(Copy.text("loginApproval")) { controls.openLoginSettings() }.buttonStyle(.link)
            }
            if let message = controls.loginError { SettingError(message: message) }
            SettingRow(Copy.text("privacy")) {
                Toggle(Copy.text("privacy"), isOn: $hideNames).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingRow(Copy.text("language")) {
                Picker(Copy.text("language"), selection: $language) {
                    Text(Copy.text("auto")).tag("auto"); Text("English").tag("en"); Text("Français").tag("fr")
                }.labelsHidden().fixedSize()
            }
        }
    }
    private var proxy: some View {
        SettingsSection(Copy.text("proxyStatus"), footer: Copy.text(controls.serviceAvailable ? "stopNote" : "serviceUnavailable")) {
            HStack(spacing: 6) {
                Circle().fill(store.error == nil && store.snapshot != nil ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(Copy.text(store.error == nil && store.snapshot != nil ? "connected" : controls.serviceAvailable && !controls.serviceRegistered ? "serviceStopped" : "notConnected"))
                Spacer()
                Button(Copy.text("start")) { Task { await controls.control(start: true, store: store) } }
                    .disabled(controls.busy || store.busy || !controls.serviceAvailable || (controls.serviceRegistered && store.error == nil))
                Button(Copy.text("stop")) { Task { await controls.control(start: false, store: store) } }
                    .disabled(controls.busy || store.busy || !controls.serviceAvailable || !controls.serviceRegistered)
            }.controlSize(.small)
            if let message = controls.serviceError { SettingError(message: message) }
        }
    }
    private var updates: some View {
        SettingsSection(Copy.text("updates"), footer: Copy.text("version") + " " + updater.versionDescription + ". " + Copy.text("updatesFooter")) {
            SettingRow(Copy.text("autoUpdate")) {
                Toggle(Copy.text("autoUpdate"), isOn: $updater.automatic).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!updater.isUpdatable)
            }
            SettingRow(Copy.text("updateBranch")) {
                Picker(Copy.text("updateBranch"), selection: $updater.branch) {
                    ForEach(SourceUpdate.branches, id: \.self) { Text(Copy.branch($0)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(!updater.isUpdatable || updater.isBusy)
            }
            HStack(spacing: 6) {
                switch updater.phase {
                case .checking, .installing: ProgressView().controlSize(.mini)
                default: EmptyView()
                }
                Text(updateStatus.text).foregroundStyle(updateStatus.failed ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                switch updater.phase {
                case .idle, .current, .development, .failed:
                    Button(Copy.text("checkNow")) { Task { await updater.check() } }.disabled(!updater.canCheck)
                case .available:
                    Button(Copy.text("installUpdate")) { Task { await updater.install() } }
                case .ready:
                    Button(Copy.text("restartNow")) { updater.restart() }
                default: EmptyView()
                }
            }.controlSize(.small)
        }
    }
    private var updateStatus: (text: String, failed: Bool) {
        let checked = updater.lastCheck.map { Copy.text("lastCheckedAt") + " " + Copy.timestamp($0, now: Date()) }
        switch updater.phase {
        case .idle: return (checked ?? "", false)
        case .checking: return (Copy.text("checking"), false)
        case .current: return ([Copy.text("upToDate"), checked].compactMap { $0 }.joined(separator: " · "), false)
        case .available: return (Copy.text("updateAvailable"), false)
        case .installing: return (Copy.text("installing"), false)
        case .ready: return (Copy.text("updateReady"), false)
        case .development: return (Copy.text("devBuild", Copy.branch(updater.branch)), false)
        case .modified: return (Copy.text("modifiedBuild"), false)
        case .unknownBuild: return (Copy.text("unknownBuild"), false)
        case .unsupported: return (Copy.text("unsupportedLocation"), false)
        case .failed(.noBranch): return (Copy.text("noBranch", Copy.branch(updater.branch)), false)
        case .failed(let error):
            let key = switch error {
            case .tools: "noTools"
            case .download: "downloadFailed"
            case .build, .verify: "buildFailed"
            case .busy: "updateBusy"
            default: "installFailed"
            }
            return (Copy.text(key), true)
        }
    }
    private var connection: some View {
        SettingsSection(Copy.text("connection"), footer: Copy.text("keyNote")) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.text("proxyURL"))
                TextField("http://127.0.0.1:8317", text: $endpoint).textFieldStyle(.roundedBorder).disabled(testing)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.text("keyFile"))
                HStack {
                    TextField("~/Library/Application Support/CLIProxyAPI/management-key", text: $keyFile).textFieldStyle(.roundedBorder).disabled(testing)
                    Button(Copy.text("choose")) {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runAboveMenu() == .OK, let url = panel.url { keyFile = url.path }
                    }
                }
            }
            if let error { SettingError(message: Copy.isFrench ? Copy.text("unknownError") : error) }
            HStack {
                Button(Copy.text(testing ? "testing" : "test")) {
                    testing = true; testPassed = nil
                    let config = Configuration(proxyURL: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                               managementKeyFile: keyFile.trimmingCharacters(in: .whitespacesAndNewlines))
                    Task {
                        do { _ = try await ProxyClient(configuration: config).testConnection(); testPassed = true }
                        catch { testPassed = false }
                        testing = false
                    }
                }.disabled(testing)
                Spacer()
                Button(Copy.text("save")) {
                    do {
                        try store.configure(Configuration(proxyURL: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          managementKeyFile: keyFile.trimmingCharacters(in: .whitespacesAndNewlines)))
                        back()
                    } catch { self.error = error.localizedDescription }
                }.disabled(store.busy || testing).buttonStyle(.borderedProminent)
            }
            if let testPassed {
                Text(Copy.text(testPassed ? "testPassed" : "testFailed")).font(.system(size: 11))
                    .foregroundStyle(testPassed ? .green : .red)
            }
        }
    }
}
