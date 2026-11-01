import SwiftUI

struct HadithFilterView: View {
    let books: [HadithCollection]?
    let chapters: [HadithChapter]
    let select: (String?, Int?) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matchingChapters: [HadithChapter] {
        let terms = QuranSearchText.terms(query)
        return chapters.filter { chapter in
            let text = QuranSearchText.normalize(chapter.arabic + " " + chapter.english + " " + chapter.bookArabic + " " + chapter.bookEnglish).lowercased()
            return query.isEmpty || (!terms.isEmpty && terms.allSatisfy { text.contains($0) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let books {
                    Button("All books") { select(nil, nil) }
                    ForEach(HadithBookGroup.allCases) { group in
                        let matches = books.filter { $0.group == group && (query.isEmpty || $0.matches(query)) }.sorted {
                            $0.title(locale: locale).compare($1.title(locale: locale), options: .numeric, locale: locale) == .orderedAscending
                        }
                        if !matches.isEmpty {
                            Section(LocalizedStringKey(group.rawValue)) {
                                ForEach(matches) { book in
                                    Button(book.title(locale: locale)) { select(book.id, nil) }
                                        .foregroundStyle(.primary)
                                        .listRowBackground(HadithBookStyle.background(for: book.id))
                                }
                            }
                        }
                    }
                } else {
                    Button("All chapters") { select(nil, nil) }
                    ForEach(matchingChapters) { chapter in
                        Button(chapter.title(locale: locale)) { select(nil, chapter.id) }
                    }
                }
            }
            .navigationTitle(books == nil ? String(localized: "Chapter") : String(localized: "Book"))
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
