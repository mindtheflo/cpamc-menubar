import AppKit
import SwiftUI

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A status-item dropdown with no popover arrow, title bar, Dock entry or independent window.
@MainActor
final class StatusMenu {
    private let panel: MenuPanel
    private let content: NSHostingController<AnyView>
    private weak var button: NSStatusBarButton?
    private let staysOpen: Bool
    private var sizeObservation: NSKeyValueObservation?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    var isVisible: Bool { panel.isVisible }

    init<Content: View>(rootView: Content, button: NSStatusBarButton, staysOpen: Bool) {
        self.button = button
        self.staysOpen = staysOpen
        panel = MenuPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        content = NSHostingController(rootView: AnyView(rootView
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))))
        content.sizingOptions = [.preferredContentSize]
        panel.contentViewController = content
        sizeObservation = content.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.position() }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.staysOpen else { return }
                self.dismiss()
            }
        }
    }

    func show() {
        guard button?.window != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        position()
        panel.makeKeyAndOrderFront(nil)
        button?.highlight(true)
        guard !staysOpen, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.dismiss(); return nil }
            if event.type != .keyDown, event.window !== self.panel, event.window !== self.button?.window {
                self.dismiss()
            }
            return event
        }
    }

    func dismiss() {
        panel.orderOut(nil)
        button?.highlight(false)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }

    private func position() {
        guard let button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let fitting = content.preferredContentSize
        let size = fitting.width > 0 && fitting.height > 0 ? fitting : content.view.fittingSize
        let visible = screen.visibleFrame
        let width = max(360, size.width)
        let height = min(max(50, size.height), visible.height - 8)
        let x = min(max(anchor.midX - width / 2, visible.minX + 4), visible.maxX - width - 4)
        let top = min(anchor.minY, visible.maxY) - 4
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
