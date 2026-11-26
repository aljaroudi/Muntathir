import AppIntents
import SwiftUI

/// Where an App Intent asked the app to go. `ContentView` applies it once its tabs exist, so a cold launch lands too.
@MainActor @Observable final class IntentRouter {
    static let shared = IntentRouter()

    enum Destination: Equatable {
        /// A tool with screens pushed above its root.
        case tool(AppTool, path: [FigureRoute] = [])
        /// A Hadith narration, opened through the persisted Hadith session.
        case hadith(HadithSource)
        /// A search term for the tool's own search field.
        case search(AppTool, String)
    }

    struct Search: Equatable {
        let tool: AppTool
        let term: String
    }

    var pending: Destination?
    /// Read by the tool's root view once it appears, then cleared.
    var search: Search?

    private init() {}

    /// Hands the pending search to the tool that asked for it.
    func takeSearch(for tool: AppTool) -> String? {
        guard let search, search.tool == tool else { return nil }
        self.search = nil
        return search.term
    }
}

extension View {
    /// Fills a tool's search field when an App Intent searches it.
    func intentSearch(_ tool: AppTool, apply: @escaping (String) -> Void) -> some View {
        onChange(of: IntentRouter.shared.search, initial: true) {
            if let term = IntentRouter.shared.takeSearch(for: tool) {
                apply(term)
            }
        }
    }

    /// Tells Siri and Apple Intelligence which entity this screen shows, so "this" refers to it.
    func onscreenEntity<Entity: AppEntity>(_ type: Entity.Type, id: Entity.ID?) -> some View {
        userActivity("com.aljaroudi.Muntathir.view." + String(describing: type), isActive: id != nil) { activity in
            if let id {
                activity.appEntityIdentifier = EntityIdentifier(for: type, identifier: id)
            }
        }
    }
}
