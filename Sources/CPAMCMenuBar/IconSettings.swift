import SwiftUI
import QuotaCore

struct IconSettings: View {
    @ObservedObject var store: QuotaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(Copy.text("iconShows"))
                InfoPill(Copy.text(store.iconPreferences.content == .providers ? "providersHint" : "windowsHint"))
            }
            Picker(Copy.text("iconShows"), selection: $store.iconPreferences.content) {
                Text(Copy.text("iconProviders")).tag(IconContent.providers)
                Text(Copy.text("iconWindows")).tag(IconContent.windows)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}
