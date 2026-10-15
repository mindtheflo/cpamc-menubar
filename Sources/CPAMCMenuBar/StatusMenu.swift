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
    private let root: AnyView
    private let content: NSHostingController<AnyView>
    private weak var button: NSStatusBarButton?
    private let staysOpen: Bool
    private var isOpen = false
    private var sizeObservation: NSKeyValueObservation?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// When the menu last closed because it lost focus, which a press on the status item also causes.
    private var lostFocusAt = Date.distantPast
    /// Where the menu hangs from, set when it opens.
    private var anchor = NSRect.zero
    var isVisible: Bool { panel.isVisible }
    /// Called after the menu closes.
    var onClose: (() -> Void)?

    init<Content: View>(rootView: Content, button: NSStatusBarButton, staysOpen: Bool) {
        self.button = button
        self.staysOpen = staysOpen
        // Opening never waits for macOS to activate the app, which it can refuse, for example
        // right after an update relaunched the app in the background.
        panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        let root = AnyView(rootView
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9)))
        self.root = root
        content = NSHostingController(rootView: AnyView(root.id(UUID())))
        content.sizingOptions = [.preferredContentSize]
        panel.contentViewController = content
        sizeObservation = content.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.position() }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // A file picker or a help popover can take focus without closing the menu.
                guard let self, self.isOpen, !self.staysOpen, NSApp.modalWindow == nil, !self.contains(NSApp.keyWindow),
                      self.panel.childWindows?.contains(where: \.isVisible) != true else { return }
                self.lostFocusAt = Date()
                self.dismiss()
            }
        }
    }

    /// Opens or closes the menu from its status item.
    func toggle() {
        // The press that took the focus away already closed the menu; it mustn't reopen it.
        if isVisible || Date().timeIntervalSince(lostFocusAt) < 0.4 { dismiss() } else { show() }
    }

    func show() {
        guard let button, let window = button.window else { return }
        isOpen = true
        // A menu bar manager such as Bartender can keep the item off screen, even right after the
        // click that opens the menu. The menu then opens where the click was.
        anchor = window.screen == nil ? NSRect(origin: NSEvent.mouseLocation, size: .zero)
            : window.convertToScreen(button.convert(button.bounds, to: nil))
        position()
        panel.orderFrontRegardless()
        panel.makeKey()
        button.highlight(true)
        guard !staysOpen, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard NSApp.modalWindow == nil else { return }
                self?.dismiss()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            // Clicks in a file picker opened from Settings belong to the picker, not outside the menu.
            guard let self, NSApp.modalWindow == nil else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.dismiss(); return nil }
            if event.type != .keyDown, !self.contains(event.window), event.window !== self.button?.window {
                self.dismiss()
            }
            return event
        }
    }

    /// Help popovers are child windows: focusing or clicking them is still inside this menu.
    private func contains(_ window: NSWindow?) -> Bool {
        var current = window
        while let candidate = current {
            if candidate === panel { return true }
            current = candidate.parent
        }
        return false
    }

    /// Closes the menu. Like a native menu, it reopens on the overview: the page, selection,
    /// scroll position and unsaved edits are discarded with the view's identity.
    func dismiss() {
        panel.orderOut(nil)
        button?.highlight(false)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        guard isOpen else { return }
        isOpen = false
        content.rootView = AnyView(root.id(UUID()))
        content.view.layoutSubtreeIfNeeded()
        onClose?()
    }

    private func position() {
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? NSScreen.main else { return }
        let fitting = content.preferredContentSize
        let size = fitting.width > 0 && fitting.height > 0 ? fitting : content.view.fittingSize
        let visible = screen.visibleFrame
        let width = max(360, size.width)
        let height = min(max(50, size.height), visible.height - 8)
        // Like other apps' menus, its left corner sits below the icon, moved left when there isn't room.
        let x = min(max(anchor.minX, visible.minX + 4), visible.maxX - width - 4)
        let top = min(anchor.minY, visible.maxY) - 4
        panel.setFrame(NSRect(x: x, y: max(visible.minY + 4, top - height), width: width, height: height), display: true)
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}

extension NSOpenPanel {
    /// Shows the picker in front of the open menu, which stays open underneath instead of closing.
    @MainActor func runAboveMenu() -> NSApplication.ModalResponse {
        let menu = NSApp.windows.first { $0 is MenuPanel && $0.isVisible }
        menu?.level = .normal
        defer { menu?.level = .popUpMenu }
        // The menu works without activating the app; the picker needs it to take the focus.
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}
