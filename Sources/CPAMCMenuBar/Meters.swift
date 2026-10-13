import AppKit
import SwiftUI
import QuotaCore

extension MeterTone {
    var color: Color {
        switch self {
        case .ok: return Color(nsColor: .systemGreen)
        case .low: return Color(nsColor: .systemOrange)
        case .out: return Color(nsColor: .systemRed)
        case .unknown: return .secondary
        }
    }
    var nativeColor: NSColor {
        switch self { case .ok: return .systemGreen; case .low: return .systemOrange; case .out: return .systemRed; case .unknown: return .secondaryLabelColor }
    }
}

struct LevelCapsule: View {
    let left: Double?
    let tone: MeterTone
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(tone == .out ? tone.color.opacity(0.3) : Color.primary.opacity(0.16))
            if let left, left > 0 {
                Rectangle().fill(tone.color).frame(height: 14 * min(100, max(0, left)) / 100)
            }
        }
        .frame(width: 4, height: 14).clipShape(Capsule()).accessibilityHidden(true)
    }
}

enum MenuIcon {
    // Same 24 × 22pt, 4pt bars, 2pt gap and runway colours as Notis Desktop.
    static func image(_ summaries: [ProviderSummary], offline: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 22), flipped: false) { rect in
            let bars = summaries.isEmpty ? [nil] : summaries.map { Optional($0) }
            let total = CGFloat(bars.count * 4 + (bars.count - 1) * 2)
            let firstY = (22 - total) / 2
            for (index, summary) in bars.enumerated() {
                let y = firstY + CGFloat(bars.count - 1 - index) * 6
                let track = NSBezierPath(roundedRect: NSRect(x: 3, y: y, width: 18, height: 4), xRadius: 2, yRadius: 2)
                let tone = offline ? MeterTone.unknown : summary?.tone ?? .unknown
                (tone == .out ? NSColor.systemRed : NSColor.secondaryLabelColor).withAlphaComponent(0.45).setFill()
                track.fill()
                if !offline, let left = summary?.leftPercent, left > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(rect: NSRect(x: 3, y: y, width: 18 * CGFloat(left / 100), height: 4)).addClip()
                    tone.nativeColor.setFill(); track.fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
