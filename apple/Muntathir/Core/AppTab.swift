enum AppTab: Hashable {
    case today, tool(AppTool), tools

    func available(in shortcuts: [AppTool]) -> AppTab {
        if case let .tool(tool) = self, !shortcuts.contains(tool) {
            return .today
        }
        return self
    }
}
