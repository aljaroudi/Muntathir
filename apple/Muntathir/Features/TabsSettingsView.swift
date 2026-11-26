import SwiftUI

struct TabsSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isShowingTabSidebar) private var isShowingTabSidebar

    var body: some View {
        List {
            Section {
                Label("Today", systemImage: "sun.max")
            }
            Section {
                ForEach(model.preferences.tabShortcuts) { tool in
                    Label { Text(tool.title) } icon: { Image(systemName: tool.symbol) }
                        .accessibilityIdentifier("tab-shortcut-\(tool.rawValue)")
                }
                .onDelete { indices in
                    model.update { $0.tabShortcuts.remove(atOffsets: indices) }
                }
                .onMove { indices, destination in
                    model.update { $0.tabShortcuts.move(fromOffsets: indices, toOffset: destination) }
                }
            } header: {
                Text("Tabs")
            } footer: {
                if isShowingTabSidebar {
                    Text("Tap Edit in the sidebar to choose which tools appear in the tab bar.")
                } else {
                    Text("Choose up to three tabs. Everything else stays in Tools.")
                }
            }
            Section {
                Label("Tools", systemImage: "square.grid.2x2")
            }
            Section("Available tabs") {
                // Distinct IDs prevent available rows from carrying their non-editable state into shortcuts.
                ForEach(AppTool.available.filter { !model.preferences.tabShortcuts.contains($0) }, id: \.self) { tool in
                    Button {
                        model.update { $0.tabShortcuts.append(tool) }
                    } label: {
                        Label { Text(tool.title) } icon: { Image(systemName: "plus.circle.fill") }
                    }
                    .disabled(model.preferences.tabShortcuts.count >= AppTool.maximumShortcuts)
                    .accessibilityIdentifier("add-tab-\(tool.rawValue)")
                }
            }
        }
        #if os(iOS)
        // Show reorder handles; Mac lists reorder by dragging without an edit mode.
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Tabs")
        .inlineNavigationTitle()
    }
}
