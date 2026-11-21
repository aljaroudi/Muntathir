import SwiftUI
import Translation

/// Small secondary header naming a translation block, shared by trusted and machine translations.
struct TranslationHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// On-demand Apple translation of one reading item. Nothing is remembered; callers reset it with `.id`.
struct MachineTranslationSection: View {
    let source: Locale.Language
    let target: Locale.Language
    let paragraphs: [String]
    /// Leading paragraphs rendered as a heading, such as a ruling's question.
    var headings = 0
    /// Render as a `List` section rather than a stacked block in a scroll view.
    var inList = false
    @Environment(\.locale) private var locale
    @State private var phase = Phase.idle
    @State private var configuration: TranslationSession.Configuration?

    private enum Phase: Equatable {
        case idle, translating, unsupported, failed
        case translated([String])
    }

    var body: some View {
        if inList {
            Section {
                content
            } header: {
                header
            } footer: {
                footer
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                content
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetName: String {
        target.languageCode.flatMap { locale.localizedString(forLanguageCode: $0.identifier) } ?? target.minimalIdentifier
    }

    @ViewBuilder private var header: some View {
        if case .translated = phase {
            TranslationHeader(title: String(localized: "Translation · \(targetName)"))
        }
    }

    @ViewBuilder private var footer: some View {
        if case .translated = phase {
            Text("Translated by Apple. Machine translations may be inaccurate; refer to the original text.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .idle:
                Button {
                    Task { await translate() }
                } label: {
                    Label("Translate to \(targetName)", systemImage: "translate")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("machine-translate")
            case .translating:
                ProgressView("Translating…")
            case .unsupported:
                Label("Translation to \(targetName) isn’t available.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Translation unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await translate() }
                }
                .buttonStyle(.bordered)
            case let .translated(texts):
                ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                    Text(verbatim: text)
                        .readingText(heading: index < headings ? 2 : nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.layoutDirection, target.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                .textSelection(.enabled)
                .accessibilityIdentifier("machine-translation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .translationTask(configuration) { session in
            do {
                let responses = try await session.translations(from: paragraphs.map { .init(sourceText: $0) })
                phase = .translated(responses.map(\.targetText))
            } catch let error as CocoaError where error.code == .userCancelled {
                // The reader declined or dismissed the language download.
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed
            }
        }
    }

    private func translate() async {
        phase = .translating
        guard await LanguageAvailability().status(from: source, to: target) != .unsupported else {
            phase = .unsupported
            return
        }
        if configuration == nil {
            configuration = .init(source: source, target: target)
        } else {
            configuration?.invalidate()
        }
    }
}
