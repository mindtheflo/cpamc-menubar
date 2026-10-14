import SwiftUI

/// A titled group of settings on one rounded card, in the manner of System Settings.
struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
    }
}

/// A setting's name beside its control, or above it when the two don't fit side by side.
struct SettingRow<Control: View>: View {
    let title: String
    let control: Control
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { Text(title).lineLimit(1); Spacer(minLength: 0); control }
            VStack(alignment: .leading, spacing: 6) { Text(title); control }
        }
    }
}

/// A setting's error, shown in the card it concerns.
struct SettingError: View {
    let message: String
    var body: some View {
        Text(message).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
}
