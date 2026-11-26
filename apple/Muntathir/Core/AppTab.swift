enum AppTab: Hashable {
    case today, tool(AppTool), tools, settings

    func available(in shortcuts: [AppTool]) -> AppTab {
        if case let .tool(tool) = self, !shortcuts.contains(tool) {
            return .today
        }
        return self
    }

    /// Without a sidebar, only shortcuts have tabs; other tools open through Tools.
    func withoutSidebar(shortcuts: [AppTool]) -> AppTab {
        switch self {
        case let .tool(tool) where !shortcuts.contains(tool): .tools
        case .settings: .tools
        default: self
        }
    }

    /// With a sidebar, every tool has its own tab and there's no Tools tab.
    func withSidebar(toolsRoot: FigureRoute?) -> AppTab {
        guard self == .tools else { return self }
        if case let .tool(tool) = toolsRoot {
            return .tool(tool)
        }
        return .today
    }
}
