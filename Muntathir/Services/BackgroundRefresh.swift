import BackgroundTasks

@MainActor enum BackgroundRefresh {
    static let identifier = "com.aljaroudi.Muntathir.refresh"
    static func schedule() {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
