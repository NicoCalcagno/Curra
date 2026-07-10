import Foundation

/// An already-persisted activity, referenced by its local ID.
struct ExistingActivity: Equatable, Sendable {
    var id: UUID
    var summary: ActivitySummary
}

enum MergeDecision: Equatable, Sendable {
    /// New activity, no match anywhere.
    case insert(ActivitySummary)
    /// Cross-source duplicate: update the existing record with the merged summary.
    case merge(existingID: UUID, merged: ActivitySummary)
    /// Exact re-import (same Strava ID / HealthKit UUID) — nothing to do.
    case skip
}

/// Pure deduplication logic between Strava and HealthKit imports.
///
/// Layer 1 — hard keys: an incoming summary whose `stravaID`/`healthKitUUID` is
/// already stored is skipped (idempotent re-imports).
/// Layer 2 — fuzzy cross-source match: same run recorded on the Watch and
/// auto-uploaded to Strava. Matches when the start times are within 5 minutes
/// AND the distances differ by less than max(200 m, 5%).
enum DeduplicationEngine {
    static let timeWindowSeconds: TimeInterval = 300
    static let distanceToleranceMeters: Double = 200
    static let distanceToleranceFraction: Double = 0.05

    private static let genericNames: Set<String> = [
        "Run", "Outdoor Run", "Morning Run", "Lunch Run",
        "Afternoon Run", "Evening Run", "Night Run"
    ]

    static func decisions(
        incoming: [ActivitySummary],
        existing: [ExistingActivity]
    ) -> [MergeDecision] {
        // Mutable view so intra-batch inserts/merges also participate in matching.
        var known = existing
        var result: [MergeDecision] = []

        for candidate in incoming {
            if isAlreadyStored(candidate, in: known) {
                result.append(.skip)
                continue
            }

            if let matchIndex = known.firstIndex(where: { isFuzzyMatch($0.summary, candidate) }) {
                let match = known[matchIndex]
                let combined = merged(existing: match.summary, incoming: candidate)
                known[matchIndex] = ExistingActivity(id: match.id, summary: combined)
                result.append(.merge(existingID: match.id, merged: combined))
            } else {
                known.append(ExistingActivity(id: UUID(), summary: candidate))
                result.append(.insert(candidate))
            }
        }
        return result
    }

    static func isAlreadyStored(_ candidate: ActivitySummary, in known: [ExistingActivity]) -> Bool {
        known.contains { existing in
            (candidate.stravaID != nil && existing.summary.stravaID == candidate.stravaID)
                || (candidate.healthKitUUID != nil
                    && existing.summary.healthKitUUID == candidate.healthKitUUID)
        }
    }

    static func isFuzzyMatch(_ a: ActivitySummary, _ b: ActivitySummary) -> Bool {
        // Only merge across sources; two runs from the same source are distinct.
        guard a.source != b.source || a.source == .merged else { return false }
        guard abs(a.startDate.timeIntervalSince(b.startDate)) <= timeWindowSeconds else {
            return false
        }
        let tolerance = max(
            distanceToleranceMeters,
            distanceToleranceFraction * max(a.distanceMeters, b.distanceMeters)
        )
        return abs(a.distanceMeters - b.distanceMeters) <= tolerance
    }

    /// Combines two records of the same run. The HealthKit side wins for body
    /// metrics (device source of truth); Strava contributes its ID, a meaningful
    /// name, and fills gaps.
    static func merged(
        existing: ActivitySummary,
        incoming: ActivitySummary
    ) -> ActivitySummary {
        let healthKitSide = existing.source == .strava ? incoming : existing
        let stravaSide = existing.source == .strava ? existing : incoming

        var result = healthKitSide
        result.stravaID = healthKitSide.stravaID ?? stravaSide.stravaID
        result.healthKitUUID = healthKitSide.healthKitUUID ?? stravaSide.healthKitUUID
        result.source = .merged

        if genericNames.contains(result.name), !genericNames.contains(stravaSide.name) {
            result.name = stravaSide.name
        }
        if result.encodedPolyline == nil || (!result.hasDetailedRoute && stravaSide.hasDetailedRoute) {
            if let polyline = stravaSide.encodedPolyline {
                result.encodedPolyline = polyline
                result.hasDetailedRoute = stravaSide.hasDetailedRoute
            }
        }
        result.elevationGainMeters = result.elevationGainMeters ?? stravaSide.elevationGainMeters
        result.averageHeartRate = result.averageHeartRate ?? stravaSide.averageHeartRate
        return result
    }
}
