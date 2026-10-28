import SwiftUI

/// Observe download requests in a View body, rather than the WindowGroup content closure.
struct QuranTranslationLifecycleView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private let store: QuranTranslationStore
    private let content: Content

    init(store: QuranTranslationStore = .shared, @ViewBuilder content: () -> Content) {
        self.store = store
        self.content = content()
    }

    var body: some View {
        content
            .task(id: "\(scenePhase)-\(locale.identifier)-\(store.downloadRequest)") {
                guard scenePhase == .active else { return }
                store.activate(languages: Locale.preferredLanguages)
                await store.downloadSelected()
            }
            .task { await store.observeDownloads() }
    }
}
