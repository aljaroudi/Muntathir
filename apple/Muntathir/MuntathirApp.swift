import SwiftUI

@main
struct MuntathirApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: AppModel
    @State private var progressStore = ProgressStore.application()
    @State private var quranStore: QuranUserStore
    init() {
        AppTip.configure()
        let model: AppModel
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let defaults = UserDefaults(suiteName: "Muntathir.UITests")!
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-state") {
                    defaults.removePersistentDomain(forName: "Muntathir.UITests")
                }
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding") {
                    defaults.set(true, forKey: "onboardingCompleted")
                    if !ProcessInfo.processInfo.arguments.contains("--ui-testing-release-notes") {
                        defaults.set(ReleaseNote.installed, forKey: ReleaseNote.seenKey)
                    }
                }
                model = AppModel(defaults: defaults, cloud: nil)
                if ProcessInfo.processInfo.arguments.contains("--marketing-capture") {
                    let locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
                    let language = locale.language.languageCode?.identifier ?? "en"
                    let translation = switch language {
                    case "ar": ""
                    case "de", "ru", "es", "zh", "fa": QuranTranslation.preferred(in: QuranTranslation.catalog, locale: locale)?.id ?? QuranTranslation.bundledID
                    default: QuranTranslation.bundledID
                    }
                    QuranTranslationStore.shared.select(translation)
                    let visibleOptional: Set<PrayerName> = ProcessInfo.processInfo.arguments.contains("--marketing-compact") ? [] : [.sunset]
                    model.update { $0.hiddenPrayers = Set(PrayerName.optionalTimes).subtracting(visibleOptional) }
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-mecca") {
                    model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
                }
            } else {
                model = AppModel(feedClient: .production())
            }
        #else
            model = AppModel(feedClient: .production())
        #endif
        _model = State(initialValue: model)
        _quranStore = State(initialValue: QuranUserStore.application())
        BackgroundRefresh.register {
            // Weather doesn't depend on the feed, so both share the short background budget.
            let location = model.location
            async let weather: Void = SharedWeatherStore.refreshInBackground(for: location)
            let refreshed = await model.refreshInBackground()
            await weather
            // Content stays fresh for the next open even when the app goes unopened for days.
            await AssetPackUpdates.shared.run(.background)
            return refreshed
        }
    }

    var body: some Scene {
        WindowGroup {
            appData {
                if model.onboardingCompleted {
                    ContentView().modifier(DictionaryLookupHost()).modifier(ReleaseNotesPrompt())
                } else {
                    OnboardingView().modifier(FreshInstallReleaseMarker())
                }
            }
            .task(id: "\(scenePhase)-\(locale.identifier)") {
                guard scenePhase == .active else { return }
                QuranTranslationStore.shared.activate(languages: Locale.preferredLanguages)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.refreshInBackground()
            }
            #if os(macOS) && DEBUG
            .background {
                if let size = Self.captureWindowSize {
                    CaptureWindowSizer(size: size)
                }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
            // Mac apps keep settings in a separate window opened with ⌘, rather than a sidebar item.
            Settings {
                appData {
                    SettingsSplitView()
                        .environment(\.isShowingTabSidebar, true)
                        .environment(\.rulingsAssets, AssetPackUpdates.shared.rulings)
                        .environment(\.hadithAssets, AssetPackUpdates.shared.hadith)
                        .environment(\.supplicationAssets, AssetPackUpdates.shared.supplications)
                }
                .frame(minWidth: 720, minHeight: 560)
            }
        #endif
    }

    #if os(macOS)
        /// 16:10 window for Mac App Store captures; 2560×1600 pixels of content on Retina.
        private static var captureWindowSize: CGSize? {
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--ui-testing"), arguments.contains("--marketing-capture") {
                    return CGSize(width: 1280, height: 800)
                }
            #endif
            return nil
        }
    #endif

    /// The stores and settings every scene reads from.
    private func appData(@ViewBuilder content: () -> some View) -> some View {
        ProgressDataView(store: progressStore) {
            QuranUserDataView(store: quranStore) {
                content()
            }
        }
        .defaultAppStorage(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? UserDefaults(suiteName: "Muntathir.UITests")! : .standard)
        .environment(model)
    }
}

#if os(macOS) && DEBUG
    /// Sizes the capture window once. macOS restores saved frames over `defaultSize`, and a fixed,
    /// non-resizable window crashes AppKit layout in the Quran split view.
    private struct CaptureWindowSizer: NSViewRepresentable {
        let size: CGSize

        func makeNSView(context _: Context) -> NSView {
            SizerView(size: size)
        }

        func updateNSView(_: NSView, context _: Context) {}

        final class SizerView: NSView {
            let size: CGSize

            init(size: CGSize) {
                self.size = size
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) is unavailable")
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window else { return }
                DispatchQueue.main.async { [size] in
                    // Store screenshots are light, like iOS; -AppleInterfaceStyle doesn't override a dark Mac.
                    NSApp.appearance = NSAppearance(named: .aqua)
                    window.setContentSize(size)
                    window.center()
                }
            }
        }
    }
#endif
