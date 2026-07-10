import Foundation

// MARK: - Shared enums (framework-free, used by pure engines and SwiftData models)

enum ActivitySource: String, Codable, Sendable {
    case strava
    case healthKit
    case merged
}

enum GoalMetric: String, Codable, CaseIterable, Sendable {
    case distance      // meters
    case duration      // seconds
    case runCount      // count
    case elevationGain // meters

    var displayName: String {
        switch self {
        case .distance: "Distance"
        case .duration: "Time"
        case .runCount: "Runs"
        case .elevationGain: "Elevation gain"
        }
    }

    var unitLabel: String {
        switch self {
        case .distance: "km"
        case .duration: "h"
        case .runCount: "runs"
        case .elevationGain: "m"
        }
    }
}

enum GoalPeriodUnit: String, Codable, CaseIterable, Sendable {
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

enum PlannedWorkoutStatus: String, Codable, Sendable {
    case pending
    case scheduledOnWatch
    case completed
    case skipped
}

enum RouteSource: String, Codable, Sendable {
    case manual
    case suggested
}

enum RaceType: String, Codable, CaseIterable, Sendable {
    case fiveK
    case tenK
    case half
}

// MARK: - ActivitySummary

/// Framework-free representation of a run, produced by the import pipelines
/// (Strava, HealthKit) and consumed by the pure engines (dedup, goals, load).
struct ActivitySummary: Equatable, Sendable {
    var startDate: Date
    var durationSeconds: Double
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var averageHeartRate: Double?
    var name: String
    var encodedPolyline: String?
    var source: ActivitySource
    var stravaID: Int64?
    var healthKitUUID: String?
    var hasDetailedRoute: Bool = false

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return durationSeconds / (distanceMeters / 1000)
    }
}
