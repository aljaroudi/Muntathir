#if os(iOS)
    import BackgroundTasks
#endif

/// Schedules app refresh on iOS. On macOS the app refreshes when its window becomes active,
/// and widgets keep their own timelines.
@MainActor enum BackgroundRefresh {
    static let identifier = "com.aljaroudi.Muntathir.refresh"
    private(set) static var isRegistered = false

    static func register(refresh: @escaping @MainActor () async -> Bool) {
        #if os(iOS)
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
        #endif
    }

    static func schedule() {
        #if os(iOS)
            // Preferences can request a refresh before app initialization finishes.
            guard isRegistered else { return }
            let arguments = ProcessInfo.processInfo.arguments
            guard
                !arguments.contains("--ui-testing")
                || arguments.contains("--ui-testing-background-refresh")
            else { return }
            Task {
                // Resubmitting replaces the pending request, so daily launches would push it back forever.
                let pending = await BGTaskScheduler.shared.pendingTaskRequests()
                guard !pending.contains(where: { $0.identifier == identifier }) else { return }
                let request = BGAppRefreshTaskRequest(identifier: identifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
                try? BGTaskScheduler.shared.submit(request)
            }
        #endif
    }
}
