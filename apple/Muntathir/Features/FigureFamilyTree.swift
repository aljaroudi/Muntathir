import SwiftUI

struct FigureFamilyTree: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var focusID: String?
    @State private var choices: [String: String] = [:]

    let originalID: String
    let library: FigureLibrary

    private var id: String {
        focusID ?? originalID
    }

    var body: some View {
        let accounts = library.parents[id, default: []].filter(\.isDefault)
        let account = accounts.count == 1 ? accounts.first : accounts.first { $0.id == choices[id] }
        let siblings = library.siblings(of: id, account: account)
        let partners = library.partners[id, default: []].filter { $0.status == .accepted }
        let children = library.childGroups(of: id, choices: choices)
        ScrollView(typeSize.isAccessibilitySize ? .vertical : [.horizontal, .vertical]) {
            VStack(spacing: 24) {
                if accounts.count > 1 {
                    Menu("Choose a parentage report") {
                        ForEach(accounts) { report in
                            Button(reportLabel(report)) { choices[id] = report.id }
                        }
                    }
                }
                if let account {
                    group("Parents") {
                        if let father = account.fatherId {
                            node(father, key: "father", role: "Father")
                        }
                        if let mother = account.motherId {
                            node(mother, key: "mother", role: "Mother")
                        }
                    }
                }
                let middle = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
                middle {
                    ForEach(FigureLibrary.SiblingDegree.allCases, id: \.self) { degree in
                        if let relatives = siblings[degree] {
                            VStack {
                                Text(degree.label).font(.caption)
                                ForEach(relatives) { person in
                                    node(person.id, key: "sibling-\(person.id)")
                                }
                            }
                        }
                    }
                    node(id, key: "focus")
                    if !partners.isEmpty {
                        VStack {
                            Text("Spouses").font(.caption)
                            ForEach(partners) { union in
                                node(union.partnerIds.first { $0 != id }, key: "partner-\(union.id)")
                            }
                        }
                    }
                }
                ForEach(children, id: \.firstID) { claims in
                    if let first = claims.first {
                        VStack(spacing: 8) {
                            if let other = first.otherParent(of: id), let person = library.byID[other] {
                                Text("Children with \(person.title(locale))").font(.caption).foregroundStyle(.secondary)
                            }
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
                            layout {
                                ForEach(claims) { claim in
                                    node(claim.childId, key: "child-\(claim.id)")
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .backgroundPreferenceValue(FigureNodeAnchors.self) { anchors in
                if !typeSize.isAccessibilitySize {
                    GeometryReader { proxy in
                        Path { path in
                            guard let focus = anchors["focus"].map({ proxy[$0] }) else { return }
                            for (key, anchor) in anchors where key != "focus" {
                                let card = proxy[anchor]
                                let isSide = key.hasPrefix("sibling-") || key.hasPrefix("partner-")
                                if isSide {
                                    let onLeft = card.midX < focus.midX
                                    path.move(to: CGPoint(x: onLeft ? focus.minX : focus.maxX, y: focus.midY))
                                    path.addLine(to: CGPoint(x: onLeft ? card.maxX : card.minX, y: card.midY))
                                } else {
                                    let above = card.midY < focus.midY
                                    let start = CGPoint(x: focus.midX, y: above ? focus.minY : focus.maxY)
                                    let end = CGPoint(x: card.midX, y: above ? card.maxY : card.minY)
                                    let branchY = above ? start.y - 12 : start.y + 12
                                    path.move(to: start)
                                    path.addLine(to: CGPoint(x: start.x, y: branchY))
                                    path.addLine(to: CGPoint(x: end.x, y: branchY))
                                    path.addLine(to: end)
                                }
                            }
                        }
                        .stroke(.secondary.opacity(0.5), lineWidth: 1)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .navigationTitle("Family tree")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                NavigationLink("View profile", value: FigureRoute.profile(id))
                if id != originalID {
                    Button("Back to original figure") { focusID = nil }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func reportLabel(_ report: FigureParentage) -> String {
        [report.fatherId, report.motherId].compactMap { id in
            id.flatMap { library.byID[$0]?.title(locale) }
        }.joined(separator: " / ")
    }

    private func group(_ label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.caption)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
            layout { content() }
        }
    }

    private func node(_ personID: String?, key: String, role: LocalizedStringKey? = nil) -> some View {
        VStack(spacing: 4) {
            if let role {
                Text(role).font(.caption).foregroundStyle(.secondary)
            }
            if let personID, let person = library.byID[personID] {
                if personID == id {
                    Text(verbatim: person.title(locale)).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button {
                        focusID = personID
                    } label: {
                        Text(verbatim: person.title(locale))
                    }
                    .accessibilityIdentifier("family-node-\(personID)")
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 200, minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(personID == id ? Color.accentColor : Color.secondary.opacity(0.3))
                .allowsHitTesting(false)
        }
        .anchorPreference(key: FigureNodeAnchors.self, value: .bounds) { [key: $0] }
    }
}

private struct FigureNodeAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] {
        [:]
    }

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
