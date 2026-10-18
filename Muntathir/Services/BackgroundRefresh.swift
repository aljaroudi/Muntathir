import BackgroundTasks

@MainActor enum BackgroundRefresh {
    static let identifier = "com.aljaroudi.Muntathir.refresh"
    private(set) static var isRegistered = false

    static func register(refresh: @escaping @MainActor () async -> Bool) {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { task in
            MainActor.assumeIsolated {
                let work = Task {
                    let succeeded = await refresh()
                    task.setTaskCompleted(
                        success: succeeded && !Task.isCancelled
                    )
                }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    static func schedule() {
        // Preferences can request a refresh before app initialization finishes.
        guard isRegistered else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard
            !arguments.contains("--ui-testing")
            || arguments.contains("--ui-testing-background-refresh")
        else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
