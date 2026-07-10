import Foundation
import SwiftData

/// A completed run. Uniqueness on `stravaID` / `healthKitUUID` is enforced by
/// `DeduplicationEngine` + coordinator lookups rather than store-level constraints,
/// so re-imports are deterministic no-ops.
@Model
final class Activity {
    var id: UUID
    var startDate: Date
    var durationSeconds: Double
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var averageHeartRate: Double?
    var name: String
    var encodedPolyline: String?
    var sourceRaw: String
    var stravaID: Int64?
    var healthKitUUID: String?
    var hasDetailedRoute: Bool

    init(summary: ActivitySummary, id: UUID = UUID()) {
        self.id = id
        self.startDate = summary.startDate
        self.durationSeconds = summary.durationSeconds
        self.distanceMeters = summary.distanceMeters
        self.elevationGainMeters = summary.elevationGainMeters
        self.averageHeartRate = summary.averageHeartRate
        self.name = summary.name
        self.encodedPolyline = summary.encodedPolyline
        self.sourceRaw = summary.source.rawValue
        self.stravaID = summary.stravaID
        self.healthKitUUID = summary.healthKitUUID
        self.hasDetailedRoute = summary.hasDetailedRoute
    }

    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .healthKit }
        set { sourceRaw = newValue.rawValue }
    }

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return durationSeconds / (distanceMeters / 1000)
    }

    var summary: ActivitySummary {
        ActivitySummary(
            startDate: startDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            averageHeartRate: averageHeartRate,
            name: name,
            encodedPolyline: encodedPolyline,
            source: source,
            stravaID: stravaID,
            healthKitUUID: healthKitUUID,
            hasDetailedRoute: hasDetailedRoute
        )
    }

    /// Copies the result of a pure merge back onto the persisted model.
    func apply(_ merged: ActivitySummary) {
        startDate = merged.startDate
        durationSeconds = merged.durationSeconds
        distanceMeters = merged.distanceMeters
        elevationGainMeters = merged.elevationGainMeters
        averageHeartRate = merged.averageHeartRate
        name = merged.name
        encodedPolyline = merged.encodedPolyline
        sourceRaw = merged.source.rawValue
        stravaID = merged.stravaID
        healthKitUUID = merged.healthKitUUID
        hasDetailedRoute = merged.hasDetailedRoute
    }
}
