import SwiftUI
import QuotaCore

struct IconSettings: View {
    @ObservedObject var store: QuotaStore
    var body: some View {
        SettingsSection(Copy.text("iconSettings"), footer: Copy.text("forecastHelp")) {
            HStack(spacing: 12) {
                Image(nsImage: MenuIcon.image(store.iconMetrics, preferences: store.iconPreferences))
                    .renderingMode(store.iconPreferences.appearance == .monochrome ? .template : .original)
                    .foregroundStyle(.primary).frame(width: 24, height: 22)
                    .accessibilityLabel(Copy.text("iconPreview"))
                Text(store.iconMetrics.map { Copy.text($0.label) + " " + ($0.isPartial && $0.leftPercent != nil ? "≥" : "") + Copy.percent($0.leftPercent) }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).help(store.iconDescription)
            SettingRow(Copy.text("iconAppearance"), help: Copy.text(store.iconPreferences.appearance == .color ? "paceLegend" : "monochromeLegend") + " " + Copy.text("forecastHelp")) {
                Picker(Copy.text("iconAppearance"), selection: $store.iconPreferences.appearance) {
                    Text(Copy.text("color")).tag(IconAppearance.color)
                    Text(Copy.text("monochrome")).tag(IconAppearance.monochrome)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingRow(Copy.text("iconShows"), help: Copy.text(store.iconPreferences.content == .providers ? "providersHint" : "windowsHint")) {
                Picker(Copy.text("iconShows"), selection: $store.iconPreferences.content) {
                    Text(Copy.text("iconProviders")).tag(IconContent.providers)
                    Text(Copy.text("iconWindows")).tag(IconContent.windows)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }
}
