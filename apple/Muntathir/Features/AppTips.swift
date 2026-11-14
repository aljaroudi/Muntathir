import OSLog
import SwiftUI
import TipKit

struct AppTip: Tip {
    enum Kind: String { case prayers, translations, reading, bookmarks }
    let kind: Kind
    var id: String {
        kind.rawValue
    }

    var title: Text {
        switch kind {
        case .prayers: Text("Prayer options")
        case .translations: Text("Translations")
        case .reading: Text("Highlights and bookmarks")
        case .bookmarks: Text("Bookmarks")
        }
    }

    var message: Text? {
        switch kind {
        case .prayers: Text("Press and hold a prayer time to mute its alert. Optional times can also be hidden.")
        case .translations: Text("Choose a translation to read alongside Arabic.")
        case .reading: Text("Select text to highlight it. Use the passage actions to add a bookmark.")
        case .bookmarks: Text("Bookmark a ruling to find it again in Saved.")
        }
    }

    var options: [any TipOption] {
        MaxDisplayCount(3)
    }

    static func complete(_ kind: Kind) {
        AppTip(kind: kind).invalidate(reason: .actionPerformed)
    }

    static var enabled: Bool {
        !ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--ui-testing-tips")
    }

    static func configure() {
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let directory = URL.applicationSupportDirectory.appending(path: "TipsUITests", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Tips.configure([.datastoreLocation(.url(directory))])
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-state") {
                    try Tips.resetDatastore()
                }
            } else {
                try Tips.configure()
            }
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "Tips").error("Unable to configure tips: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor @Observable private final class TipPresentation {
    static let shared = TipPresentation()
    var owner: UUID?
}

private struct AppTipModifier: ViewModifier {
    let tip: AppTip
    let enabled: Bool
    @State private var owner = UUID()
    @State private var eligible = false
    @State private var visible = false
    private let presentation = TipPresentation.shared

    func body(content: Content) -> some View {
        content
            .popoverTip(presentation.owner == owner ? tip : nil)
            .task(id: enabled) {
                guard enabled, AppTip.enabled else {
                    eligible = false
                    claim()
                    return
                }
                visible = true
                for await value in tip.shouldDisplayUpdates {
                    guard !Task.isCancelled else { return }
                    eligible = value
                    claim()
                }
            }
            .onChange(of: presentation.owner) { claim() }
            .onDisappear {
                visible = false
                if presentation.owner == owner {
                    presentation.owner = nil
                }
            }
    }

    private func claim() {
        if visible, eligible, presentation.owner == nil {
            presentation.owner = owner
        }
        if !eligible, presentation.owner == owner {
            presentation.owner = nil
        }
    }
}

extension View {
    func appTip(_ kind: AppTip.Kind, enabled: Bool = true) -> some View {
        modifier(AppTipModifier(tip: AppTip(kind: kind), enabled: enabled))
    }
}
