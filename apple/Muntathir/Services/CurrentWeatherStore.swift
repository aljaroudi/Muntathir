import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class CurrentWeatherStore {
    private(set) var reading: WeatherReading?
    private(set) var isLoading = false
    private(set) var failed = false
    private var location: SavedLocation?
    private var fetchedAt: Date?
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private let publish: (WeatherReading, SavedLocation) -> Void
    private let fetch: (SavedLocation) async throws -> WeatherReading

    init(publish: @escaping (WeatherReading, SavedLocation) -> Void = { reading, location in
        SharedWeatherStore.write(reading, for: location)
        WidgetCenter.shared.reloadTimelines(ofKind: "IslamicCalendar")
    }, fetch: @escaping (SavedLocation) async throws -> WeatherReading = WeatherReading.fetch) {
        self.fetch = fetch
        self.publish = publish
    }

    func refresh(location newLocation: SavedLocation?, now: Date = .now, force: Bool = false) async {
        if location != newLocation {
            task?.cancel()
            requestID = UUID()
            location = newLocation
            reading = nil
            fetchedAt = nil
            isLoading = false
            failed = false
        }
        guard let newLocation else { return }
        guard !isLoading, force || fetchedAt == nil || now.timeIntervalSince(fetchedAt!) >= 900 else { return }
        let id = UUID()
        requestID = id
        isLoading = true
        failed = false
        let work = Task { [weak self, fetch] in
            do {
                let result = try await fetch(newLocation)
                guard let self, requestID == id, !Task.isCancelled else { return }
                reading = result
                publish(result, newLocation)
                fetchedAt = now
                isLoading = false
            } catch {
                guard let self, requestID == id, !Task.isCancelled else { return }
                failed = true
                isLoading = false
            }
        }
        task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if requestID == id {
            isLoading = false
        }
    }
}
