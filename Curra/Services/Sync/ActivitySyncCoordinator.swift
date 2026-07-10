import Foundation
import SwiftData

/// Single entry point for getting activities into SwiftData from both sources.
/// Fetch → dedup (pure) → apply decisions → save. All on the main actor: a
/// personal dataset is small enough that background contexts are not worth it.
@MainActor
@Observable
final class ActivitySyncCoordinator {
    private let modelContext: ModelContext
    private let healthKit = HealthKitService.shared
    private let strava = StravaImportService.shared

    private(set) var isSyncing = false
    private(set) var stravaImportedCount: Int?
    private(set) var lastError: String?

    /// Invoked after any successful data change (used to refresh widget snapshots).
    var onDataChanged: (() -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Lifecycle

    /// Called at launch: request permissions, register the observer, run a delta sync.
    func start() async {
        guard healthKit.isAvailable else { return }
        do {
            try await healthKit.requestAuthorization()
        } catch {
            lastError = error.localizedDescription
            return
        }

        healthKit.startObservingNewWorkouts { [weak self] in
            Task { @MainActor in
                await self?.runHealthKitSync()
            }
        }
        await runHealthKitSync()
    }

    // MARK: - Sync operations

    func runHealthKitSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await healthKit.fetchNewRunningWorkouts()
            try apply(incoming: result.summaries)
            healthKit.commitAnchor(result.anchor)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runStravaFullImport() async {
        guard !isSyncing else { return }
        isSyncing = true
        stravaImportedCount = 0
        defer { isSyncing = false }

        do {
            let summaries = try await strava.fullImport { [weak self] count in
                Task { @MainActor in self?.stravaImportedCount = count }
            }
            try apply(incoming: summaries)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runStravaIncrementalSync() async {
        guard !isSyncing, StravaAuthService.shared.isConnected else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let latest = try latestStravaStartDate() ?? .distantPast
            let summaries = try await strava.activities(after: latest)
            try apply(incoming: summaries)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// On-demand enrichment: replace a summary polyline with the full GPS stream.
    func loadDetailedRoute(for activity: Activity) async {
        guard let stravaID = activity.stravaID, !activity.hasDetailedRoute else { return }
        do {
            if let polyline = try await strava.fetchDetailedPolyline(stravaID: stravaID) {
                activity.encodedPolyline = polyline
                activity.hasDetailedRoute = true
                try modelContext.save()
                onDataChanged?()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    private func apply(incoming: [ActivitySummary]) throws {
        guard !incoming.isEmpty else { return }

        let stored = try modelContext.fetch(FetchDescriptor<Activity>())
        let existing = stored.map { ExistingActivity(id: $0.id, summary: $0.summary) }
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

        for decision in DeduplicationEngine.decisions(incoming: incoming, existing: existing) {
            switch decision {
            case .insert(let summary):
                modelContext.insert(Activity(summary: summary))
            case .merge(let existingID, let merged):
                byID[existingID]?.apply(merged)
            case .skip:
                continue
            }
        }
        try modelContext.save()
        onDataChanged?()
    }

    private func latestStravaStartDate() throws -> Date? {
        var descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.stravaID != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.startDate
    }
}
