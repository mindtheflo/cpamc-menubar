import AppKit
import SwiftUI
import Combine
import ServiceManagement

@main
@MainActor
struct CPAMCMenuBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MenuBarDelegate: NSObject, NSApplicationDelegate {
    private var store: QuotaStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = QuotaStore(demo: CommandLine.arguments.contains("--demo"))
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("CPAMC Menu Bar")
            button.toolTip = "CPAMC · Made for Notis"
        }
        popover.behavior = CommandLine.arguments.contains("--show-menu") ? .applicationDefined : .transient
        let content = NSHostingController(rootView: SubscriptionPanel(store: store))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 360, height: 440)
        observation = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
        updateIcon()
        store.start()
        if CommandLine.arguments.contains("--enable-login") {
            do { try SMAppService.mainApp.register() }
            catch { fputs("Could not enable launch at login. Use the app Settings.\n", stderr) }
        }
        if CommandLine.arguments.contains("--disable-login") {
            Task { try? await SMAppService.mainApp.unregister(); NSApp.terminate(nil) }
        }
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }
    private func updateIcon() {
        statusItem.button?.image = MenuIcon.image(store.summaries, offline: store.error != nil)
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "cpamc-menubar" && $0.host == "subscriptions" }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }
}
