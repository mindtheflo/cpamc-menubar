import AppKit
import SwiftUI
import QuotaCore

struct ConnectionSettings: View {
    @ObservedObject var store: QuotaStore
    let back: () -> Void
    @State private var endpoint = ""
    @State private var keyFile = ""
    @State private var error: String?
    @State private var testing = false
    @State private var testPassed: Bool?
    @StateObject private var controls = DesktopControls()
    @AppStorage("hideAccountNames") private var hideNames = false
    @AppStorage("language") private var language = "auto"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) { Label(Copy.text("back"), systemImage: "chevron.left") }.buttonStyle(.plain)
            HStack {
                Circle().fill(store.error == nil && store.snapshot != nil ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(Copy.text("proxyStatus")).fontWeight(.semibold)
                Text(Copy.text(store.error == nil && store.snapshot != nil ? "connected" : controls.serviceAvailable && !controls.serviceRegistered ? "serviceStopped" : "notConnected")).foregroundStyle(.secondary)
                Spacer()
                Button(Copy.text("start")) { Task { await controls.control(start: true, store: store) } }
                    .disabled(controls.busy || store.busy || !controls.serviceAvailable || (controls.serviceRegistered && store.error == nil))
                Button(Copy.text("stop")) { Task { await controls.control(start: false, store: store) } }
                    .disabled(controls.busy || store.busy || !controls.serviceAvailable || !controls.serviceRegistered)
            }.controlSize(.small)
            Text(Copy.text(controls.serviceAvailable ? "stopNote" : "serviceUnavailable"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let message = controls.message { Text(message).font(.system(size: 11)).foregroundStyle(.red) }
            Divider()
            Toggle(Copy.text("launchAtLogin"), isOn: Binding(get: { controls.loginEnabled }, set: { value in
                Task { await controls.setLogin(value, configuration: store.configuration) }
            })).disabled(controls.busy)
            if controls.loginApprovalRequired {
                Button(Copy.text("loginApproval")) { controls.openLoginSettings() }.buttonStyle(.link)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.text("proxyURL")).foregroundStyle(.secondary)
                TextField("http://127.0.0.1:8317", text: $endpoint).textFieldStyle(.roundedBorder).disabled(testing)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.text("keyFile")).foregroundStyle(.secondary)
                HStack {
                    TextField("~/Library/Application Support/CLIProxyAPI/management-key", text: $keyFile).textFieldStyle(.roundedBorder).disabled(testing)
                    Button(Copy.text("choose")) {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { keyFile = url.path }
                    }
                }
            }
            Text(Copy.text("keyNote")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(Copy.text("privacy"), isOn: $hideNames)
            Picker(Copy.text("language"), selection: $language) {
                Text(Copy.text("auto")).tag("auto"); Text("English").tag("en"); Text("Français").tag("fr")
            }
            if let error { Text(Copy.isFrench ? Copy.text("unknownError") : error).foregroundStyle(.red).font(.system(size: 11)) }
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
        }.padding(10)
        .onChange(of: endpoint) { _ in testPassed = nil }
        .onChange(of: keyFile) { _ in testPassed = nil }
        .task { await controls.refresh(configuration: store.configuration) }.onAppear { endpoint = store.configuration.proxyURL; keyFile = store.configuration.managementKeyFile }
    }
}
