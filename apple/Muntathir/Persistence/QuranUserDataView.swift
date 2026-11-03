import SwiftData
import SwiftUI

extension EnvironmentValues {
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
                QuranAnnotationObserver(store: store) { content }
                    .modelContainer(container)
            } else {
                content
            }
        }
        .environment(\.quranUserStore, store)
    }
}

private struct QuranAnnotationObserver<Content: View>: View {
    let store: QuranUserStore
    @ViewBuilder let content: Content
    @Query private var annotations: [QuranAnnotation]
    @Query private var hadithAnnotations: [HadithAnnotation]

    var body: some View {
        content.onChange(of: annotations.map(QuranAnnotationSnapshot.init), initial: true) { _, rows in
            store.receive(rows)
        }
        .onChange(of: hadithAnnotations.map(QuranAnnotationSnapshot.init), initial: true) { _, rows in
            store.receiveHadith(rows)
        }
    }
}
