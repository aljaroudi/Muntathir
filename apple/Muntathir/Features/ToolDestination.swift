import SwiftUI

struct ToolDestination: View {
    let tool: AppTool
    @Environment(\.hadithAssets) private var hadithAssets
    @Environment(\.supplicationAssets) private var supplicationAssets

    var body: some View {
        switch tool {
        case .calendar: CalendarScreen()
        case .events: EventsView()
        case .quran: QuranView()
        case .rulings: RulingsView()
        case .hadith:
            if let hadithAssets {
                HadithLibraryView(assets: hadithAssets)
            }
        case .supplications:
            if let supplicationAssets {
                HadithLibraryView(assets: supplicationAssets, supplications: true)
                    .environment(\.hadithAssets, supplicationAssets)
                    .environment(\.hadithSession, nil)
            }
        case .sermons: SermonsView()
        case .figures: FigureBrowser()
        case .tasbih: TasbihView()
        case .rakaat:
            #if os(iOS)
                RakaatTrackerView()
            #endif
        case .prayerProgress: ActivityProgressView()
        case .qibla:
            #if os(iOS)
                QiblaView()
            #endif
        }
    }
}
