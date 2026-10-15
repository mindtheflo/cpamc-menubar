import AppKit
import SwiftUI

/// A native help control: no dependency on inactive-window tooltips or transient popover dismissal.
struct InfoPill: NSViewRepresentable {
    let message: String
    init(_ message: String) { self.message = message }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InfoButton, context: Context) -> CGSize? {
        CGSize(width: 20, height: 16)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> InfoButton {
        let button = InfoButton(title: "i", target: context.coordinator, action: #selector(Coordinator.toggle))
        button.bezelStyle = .inline
        button.controlSize = .mini
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.setAccessibilityLabel(Copy.text("moreInfo"))
        button.hover = { [weak coordinator = context.coordinator] in coordinator?.hover($0) }
        context.coordinator.button = button
        return button
    }
    func updateNSView(_ button: InfoButton, context: Context) {
        button.setAccessibilityHelp(message)
        context.coordinator.message = message
    }
    static func dismantleNSView(_ button: InfoButton, coordinator: Coordinator) { coordinator.close() }

    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        private static weak var active: Coordinator?
        weak var button: InfoButton?
        var message = ""
        private var pinned = false
        private var pending: Task<Void, Never>?
        private var popover: NSPopover?

        @objc func toggle() {
            pending?.cancel()
            if pinned { close() }
            else { pinned = true; show() }
        }
        func hover(_ inside: Bool) {
            pending?.cancel()
            guard !pinned else { return }
            pending = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: inside ? 400_000_000 : 300_000_000) }
                catch { return }
                if inside { show() } else { close() }
            }
        }
        private func show() {
            guard let button, button.window?.isVisible == true else { return }
            guard popover?.isShown != true else { return }
            Self.active?.close()
            Self.active = self
            let popover = NSPopover()
            // The menu owns outside-click and Escape dismissal; clicking the pill must not close help first.
            popover.behavior = .applicationDefined
            popover.animates = false
            popover.delegate = self
            let controller = NSViewController()
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.isSelectable = true
            let height = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 280, height: 10_000)).height)
            let content = HelpContentView(frame: NSRect(x: 0, y: 0, width: 304, height: height + 24))
            content.hover = { [weak self] in self?.hover($0) }
            label.frame = NSRect(x: 12, y: 12, width: 280, height: height)
            content.addSubview(label)
            controller.view = content
            popover.contentViewController = controller
            self.popover = popover
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        func close() {
            pending?.cancel()
            pinned = false
            popover?.close()
            popover = nil
            if Self.active === self { Self.active = nil }
        }
        func popoverDidClose(_ notification: Notification) {
            pinned = false
            pending?.cancel()
            if Self.active === self { Self.active = nil }
        }
    }
}

/// Active-always tracking also works when another app owns activation.
final class InfoButton: NSButton {
    var hover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 16) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
}

private final class HelpContentView: NSView {
    var hover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
}
