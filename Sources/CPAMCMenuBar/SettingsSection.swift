import SwiftUI

/// Supporting explanations stay in a hover tooltip, outside the compact settings layout.
struct InfoPill: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text("i").font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary).frame(width: 20, height: 16)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule()).help(message)
            .accessibilityLabel(Copy.text("moreInfo"))
            .accessibilityValue(message)
    }
}

/// A titled group of native settings; supporting explanations live in its info pill.
struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if let footer { InfoPill(footer) }
            }.padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A setting's name beside its control, or above it when the two don't fit side by side.
struct SettingRow<Control: View>: View {
    let title: String
    let help: String?
    let control: Control
    init(_ title: String, help: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.help = help; self.control = control()
    }
    private var label: some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1)
            if let help { InfoPill(help) }
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { label; Spacer(minLength: 0); control }
            VStack(alignment: .leading, spacing: 6) { label; control }
        }
    }
}

struct SettingError: View {
    let message: String
    var body: some View {
        Text(message).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
}
