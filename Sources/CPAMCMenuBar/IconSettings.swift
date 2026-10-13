import SwiftUI
import QuotaCore

struct IconSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: QuotaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.text("iconSettings")).fontWeight(.semibold)
            HStack(spacing: 12) {
                Image(nsImage: MenuIcon.image(store.iconMetrics, preferences: store.iconPreferences, dark: colorScheme == .dark))
                    .renderingMode(.original)
                    .foregroundStyle(.primary).frame(width: 24, height: 22)
                    .accessibilityLabel(Copy.text("iconPreview"))
                Text(store.iconDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            Picker(Copy.text("orientation"), selection: $store.iconPreferences.orientation) {
                Text(Copy.text("vertical")).tag(IconOrientation.vertical)
                Text(Copy.text("horizontal")).tag(IconOrientation.horizontal)
            }.pickerStyle(.segmented)
            Picker(Copy.text("iconAppearance"), selection: $store.iconPreferences.appearance) {
                Text(Copy.text("color")).tag(IconAppearance.color)
                Text(Copy.text("monochrome")).tag(IconAppearance.monochrome)
            }.pickerStyle(.segmented)
            Text(Copy.text("iconShows")).foregroundStyle(.secondary)
            Picker(Copy.text("iconShows"), selection: $store.iconPreferences.content) {
                Text(Copy.text("iconProviders")).tag(IconContent.providers)
                Text(Copy.text("iconWindows")).tag(IconContent.windows)
            }.pickerStyle(.segmented).labelsHidden()
            Text(Copy.text(store.iconPreferences.content == .providers ? "providersHint" : "windowsHint"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(Copy.text(store.iconPreferences.orientation == .vertical ? "verticalOrder" : "horizontalOrder"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
