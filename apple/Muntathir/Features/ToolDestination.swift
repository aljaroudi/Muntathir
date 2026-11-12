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
        case .figures: FigureBrowser()
        case .tasbih: TasbihView()
        case .rakaat: RakaatTrackerView()
        case .qibla: QiblaView()
        }
    }
}
