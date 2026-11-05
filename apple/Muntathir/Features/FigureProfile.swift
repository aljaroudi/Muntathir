import SwiftUI

extension Figure.NameKind {
    var label: LocalizedStringKey {
        switch self {
        case .personal: "Personal names"
        case .full: "Name"
        case .surname: "Surnames"
        case .kunya: "Kunyas"
        case .laqab: "Laqabs"
        case .nisba: "Nisbas"
        case .nickname: "Nicknames"
        case .title: "Titles"
        }
    }
}

extension FigureLibrary.SiblingDegree {
    var label: LocalizedStringKey {
        switch self {
        case .full: "Full siblings"
        case .half: "Half-siblings"
        case .unknown: "Siblings of uncertain degree"
        }
    }
}

struct FigureProfile: View {
    @Environment(\.locale) private var locale
    let figure: Figure
    let library: FigureLibrary

    var body: some View {
        let id = figure.id
        let parents = library.parents[id, default: []]
        let primary = parents.filter(\.isDefault)
        let siblings = library.siblings(of: id, account: primary.count == 1 ? primary.first : nil)
        List {
            NavigationLink(value: FigureRoute.tree(id)) {
                Label("Family tree", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .accessibilityIdentifier("figure-family-tree")
            ForEach(Figure.NameKind.allCases.filter { $0 != .personal }, id: \.self) { kind in
                let names = figure.names(kind, locale: locale)
                if !names.isEmpty {
                    Section(kind.label) {
                        ForEach(Array(Set(names)).sorted(), id: \.self) { name in Text(verbatim: name) }
                    }
                }
            }
            dateSection("Birth dates", dates: figure.birthDates)
            dateSection("Death dates", dates: figure.deathDates)
            if let notes = figure.notes.flatMap({ Figure.localized($0, locale) }) {
                Section("Notes") { Text(verbatim: notes) }
            }
            if !parents.isEmpty {
                Section("Parents") {
                    ForEach(parents) { claim in
                        relative(claim.fatherId, role: "Father")
                        relative(claim.motherId, role: "Mother")
                    }
                }
            }
            let unions = library.partners[id, default: []]
            if !unions.isEmpty {
                Section("Spouses") {
                    ForEach(unions) { union in
                        relative(union.partnerIds.first { $0 != id })
                    }
                }
            }
            ForEach(FigureLibrary.SiblingDegree.allCases, id: \.self) { degree in
                if let people = siblings[degree] {
                    Section(degree.label) {
                        ForEach(people) { person in relative(person.id) }
                    }
                }
            }
            ForEach(library.childGroups(of: id), id: \.firstID) { claims in
                Section {
                    ForEach(claims) { claim in relative(claim.childId) }
                } header: {
                    if let other = claims.first?.otherParent(of: id), let person = library.byID[other] {
                        Text("Children with \(person.title(locale))")
                    } else {
                        Text("Children")
                    }
                }
            }
            let defaultChildIDs = Set(library.childGroups(of: id).flatMap { $0.map(\.id) })
            let otherClaims = library.children[id, default: []].filter { !defaultChildIDs.contains($0.id) }
            if !otherClaims.isEmpty {
                Section("Other parentage reports") {
                    ForEach(otherClaims) { claim in
                        VStack(alignment: .leading, spacing: 6) {
                            relative(claim.childId)
                            relative(claim.otherParent(of: id), role: "Other parent")
                        }
                    }
                }
            }
            if let events = library.events[id] {
                Section("Related observances") {
                    ForEach(events) { event in
                        VStack(alignment: .leading) {
                            Text(verbatim: event.title(locale: locale))
                            Text(verbatim: FigureDateView.hijriDay(event.day, month: event.month, locale: locale))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(figure.title(locale))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func relative(_ id: String?, role: LocalizedStringKey? = nil) -> some View {
        if let id, let person = library.byID[id] {
            NavigationLink(value: FigureRoute.profile(id)) {
                if let role {
                    LabeledContent(role) { Text(verbatim: person.title(locale)) }
                } else {
                    Text(verbatim: person.title(locale))
                }
            }
        }
    }

    @ViewBuilder
    private func dateSection(_ label: LocalizedStringKey, dates: [FigureDate]) -> some View {
        if !dates.isEmpty {
            Section(label) { dateRows(dates) }
        }
    }

    private func dateRows(_ dates: [FigureDate]) -> some View {
        ForEach(dates, id: \.self) { date in FigureDateView(date: date) }
    }
}

extension [FigureParentage] {
    var firstID: String? {
        first?.id
    }
}
