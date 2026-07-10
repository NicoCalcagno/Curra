import CoreLocation
import Foundation
import HealthKit

enum HealthKitError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health data is not available on this device."
        }
    }
}

/// Read-only HealthKit adapter: running workouts + GPS routes, incremental via
/// a persisted `HKQueryAnchor`, plus observer-based auto-sync for new Watch runs.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let anchorKey = "healthkit.workoutAnchor"
    private var observerQuery: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let readTypes: Set<HKObjectType> = [
            .workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Incremental fetch

    struct FetchResult {
        var summaries: [ActivitySummary]
        var anchor: HKQueryAnchor?
    }

    /// Fetches running workouts added since the last committed anchor.
    /// Call `commitAnchor` only after the summaries have been persisted, so an
    /// interrupted sync retries the same delta.
    func fetchNewRunningWorkouts() async throws -> FetchResult {
        guard isAvailable else { throw HealthKitError.unavailable }

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForWorkouts(with: .running))],
            anchor: loadAnchor()
        )
        let result = try await descriptor.result(for: store)

        var summaries: [ActivitySummary] = []
        for workout in result.addedSamples {
            summaries.append(await summary(for: workout))
        }
        return FetchResult(summaries: summaries, anchor: result.newAnchor)
    }

    func commitAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(
                withRootObject: anchor,
                requiringSecureCoding: true
              )
        else { return }
        UserDefaults.standard.set(data, forKey: anchorKey)
    }

    // MARK: - Observation (auto-sync of new Watch runs)

    /// Registers an observer + background delivery. The handler fires on any new
    /// running workout; the anchored fetch then picks up the actual delta, so it
    /// is safe to complete the observer immediately.
    func startObservingNewWorkouts(_ handler: @escaping @Sendable () -> Void) {
        guard isAvailable, observerQuery == nil else { return }

        let query = HKObserverQuery(
            sampleType: .workoutType(),
            predicate: HKQuery.predicateForWorkouts(with: .running)
        ) { _, completionHandler, error in
            if error == nil { handler() }
            completionHandler()
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, _ in }
    }

    // MARK: - Mapping

    private func summary(for workout: HKWorkout) async -> ActivitySummary {
        let distance = workout
            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0

        let heartRate = workout
            .statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        let elevation = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())

        let polyline = try? await encodedRoute(for: workout)

        return ActivitySummary(
            startDate: workout.startDate,
            durationSeconds: workout.duration,
            distanceMeters: distance,
            elevationGainMeters: elevation,
            averageHeartRate: heartRate,
            name: Self.defaultName(for: workout.startDate),
            encodedPolyline: polyline ?? nil,
            source: .healthKit,
            healthKitUUID: workout.uuid.uuidString,
            hasDetailedRoute: polyline != nil
        )
    }

    static func defaultName(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "Morning Run"
        case 11..<14: "Lunch Run"
        case 14..<18: "Afternoon Run"
        case 18..<23: "Evening Run"
        default: "Night Run"
        }
    }

    // MARK: - Route loading

    private func encodedRoute(for workout: HKWorkout) async throws -> String? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .sample(
                    type: HKSeriesType.workoutRoute(),
                    predicate: HKQuery.predicateForObjects(from: workout)
                )
            ],
            sortDescriptors: []
        )
        let samples = try await descriptor.result(for: store)
        guard let route = samples.compactMap({ $0 as? HKWorkoutRoute }).first else {
            return nil
        }

        let locations = try await locations(for: route)
        guard !locations.isEmpty else { return nil }

        let coordinates = Self.downsample(locations, minimumDistance: 10)
            .map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        return Polyline.encode(coordinates)
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        let stream = AsyncThrowingStream<[CLLocation], Error> { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                if let batch { continuation.yield(batch) }
                if done { continuation.finish() }
            }
            store.execute(query)
        }

        var all: [CLLocation] = []
        for try await batch in stream {
            all.append(contentsOf: batch)
        }
        return all
    }

    /// Keeps roughly one point every `minimumDistance` meters (plus endpoints)
    /// to bound polyline size for long runs.
    static func downsample(_ locations: [CLLocation], minimumDistance: Double) -> [CLLocation] {
        guard let first = locations.first else { return [] }
        var kept: [CLLocation] = [first]
        for location in locations.dropFirst() {
            if location.distance(from: kept[kept.count - 1]) >= minimumDistance {
                kept.append(location)
            }
        }
        if let last = locations.last, kept.last !== last {
            kept.append(last)
        }
        return kept
    }

    // MARK: - Private

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
