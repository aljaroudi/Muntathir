#if DEBUG
    import Foundation

    /// Launch-only clock for repeatable screenshots and continuous simulator previews.
    struct CaptureClock {
        let start: Date
        let end: Date
        let beginsAt: Date
        let duration: TimeInterval

        init?(arguments: [String] = ProcessInfo.processInfo.arguments) {
            func value(_ name: String) -> String? {
                guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
            guard arguments.contains("--ui-testing"),
                  let text = value("--sky-date"), let start = ISO8601DateFormatter().date(from: text) else { return nil }
            self.start = start
            end = value("--sky-end").flatMap { ISO8601DateFormatter().date(from: $0) } ?? start
            duration = value("--sky-duration").flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 20
            beginsAt = value("--sky-begins-at").flatMap(Double.init).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil } ?? .now
        }

        var isAnimated: Bool {
            end > start
        }

        func date(at wallTime: Date) -> Date {
            let progress = min(1, max(0, wallTime.timeIntervalSince(beginsAt) / duration))
            return start.addingTimeInterval(max(0, end.timeIntervalSince(start)) * progress)
        }
    }
#endif
