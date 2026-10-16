import SwiftUI
import QuotaCore

struct IconSettings: View {
    @ObservedObject var store: QuotaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.text("iconShows"))
            Picker(Copy.text("iconShows"), selection: $store.iconPreferences.content) {
                Text(Copy.text("iconProviders")).tag(IconContent.providers)
                Text(Copy.text("iconWindows")).tag(IconContent.windows)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}
