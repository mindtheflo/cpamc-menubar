import AppKit
import SwiftUI
import QuotaCore

extension MeterTone {
    var color: Color {
        switch self {
        case .ok: return Color(nsColor: .systemGreen)
        case .low, .overPace: return Color(nsColor: .systemOrange)
        case .out: return Color(nsColor: .systemRed)
        case .underPace: return Color(nsColor: .systemBlue)
        case .unknown: return .secondary
        }
    }
    var nativeColor: NSColor {
        switch self {
        case .ok: return .systemGreen; case .low, .overPace: return .systemOrange; case .out: return .systemRed
        case .underPace: return .systemBlue; case .unknown: return .secondaryLabelColor
        }
    }
}

extension IconMetric {
    var nativeColor: NSColor {
        let original = tone.nativeColor
        guard tone != .unknown, tone != .out,
              let rgb = original.usingColorSpace(.deviceRGB) else { return original }
        var hue: CGFloat = 0, chroma: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &chroma, brightness: &brightness, alpha: &alpha)
        return NSColor(deviceHue: hue, saturation: chroma * saturation, brightness: brightness, alpha: alpha)
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
    static func image(_ metrics: [IconMetric], preferences: IconPreferences) -> NSImage {
        // Content determines geometry: providers stacked, allowance windows side by side.
        let vertical = preferences.content == .windows
        let image = NSImage(size: NSSize(width: 24, height: 22), flipped: false) { _ in
            for (index, metric) in metrics.prefix(2).enumerated() {
                let rect = vertical
                    ? NSRect(x: 4.5 + CGFloat(index) * 9, y: 2, width: 6, height: 18)
                    : NSRect(x: 3, y: 12.5 - CGFloat(index) * 9, width: 18, height: 6)
                let capsule = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
                let ink = metric.nativeColor
                // Empty and unknown retain an outline; the tooltip distinguishes them.
                ink.setStroke()
                capsule.lineWidth = 1
                capsule.stroke()
                if let left = metric.leftPercent, left > 0 {
                    let fraction = CGFloat(min(100, max(0, left)) / 100)
                    let fill = vertical
                        ? NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * fraction)
                        : NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
                    NSGraphicsContext.saveGraphicsState()
                    capsule.addClip()
                    ink.setFill(); NSBezierPath(rect: fill).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
