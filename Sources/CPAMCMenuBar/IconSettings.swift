import SwiftUI
import QuotaCore

struct IconSettings: View {
    @ObservedObject var store: QuotaStore
    var body: some View {
        SettingsSection(Copy.text("iconSettings"), footer: [
            Copy.text(store.iconPreferences.content == .providers ? "providersHint" : "windowsHint"),
            Copy.text(store.iconPreferences.orientation == .vertical ? "verticalOrder" : "horizontalOrder"),
            Copy.text(store.iconPreferences.appearance == .color ? "paceLegend" : "monochromeLegend"),
        ].joined(separator: " ")) {
            HStack(spacing: 12) {
                Image(nsImage: MenuIcon.image(store.iconMetrics, preferences: store.iconPreferences))
                    .renderingMode(store.iconPreferences.appearance == .monochrome ? .template : .original)
                    .foregroundStyle(.primary).frame(width: 24, height: 22)
                    .accessibilityLabel(Copy.text("iconPreview"))
                Text(store.iconDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            SettingRow(Copy.text("orientation")) {
                Picker(Copy.text("orientation"), selection: $store.iconPreferences.orientation) {
                    Text(Copy.text("vertical")).tag(IconOrientation.vertical)
                    Text(Copy.text("horizontal")).tag(IconOrientation.horizontal)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingRow(Copy.text("iconAppearance")) {
                Picker(Copy.text("iconAppearance"), selection: $store.iconPreferences.appearance) {
                    Text(Copy.text("color")).tag(IconAppearance.color)
                    Text(Copy.text("monochrome")).tag(IconAppearance.monochrome)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingRow(Copy.text("iconShows")) {
                Picker(Copy.text("iconShows"), selection: $store.iconPreferences.content) {
                    Text(Copy.text("iconProviders")).tag(IconContent.providers)
                    Text(Copy.text("iconWindows")).tag(IconContent.windows)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }
}
