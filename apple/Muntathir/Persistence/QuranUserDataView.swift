import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var supplicationAssets: HadithAssetStore? = nil
    @Entry var hadithAssets: HadithAssetStore? = nil
    @Entry var hadithSession: HadithSession? = nil
    @Entry var quranUserStore: QuranUserStore? = nil
}

struct QuranUserDataView<Content: View>: View {
    let store: QuranUserStore
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if let container = store.container {
                HighlightObserver(store: store) { content }
                    .modelContainer(container)
            } else {
                content
            }
        }
        .environment(\.quranUserStore, store)
    }
}

private struct HighlightObserver<Content: View>: View {
    let store: QuranUserStore
    @ViewBuilder let content: Content
    @Query private var annotations: [HighlightRecord]

    var body: some View {
        content.onChange(of: annotations.map(HighlightSnapshot.init), initial: true) { _, rows in
            store.receive(rows)
        }
    }
}
