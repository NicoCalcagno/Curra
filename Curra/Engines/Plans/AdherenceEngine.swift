import Foundation

/// Pure matching between planned workouts and completed activities.
enum AdherenceEngine {
    struct PlannedSnapshot: Equatable, Sendable {
        var id: UUID
        var date: Date
        var estimatedDistanceMeters: Double
        var status: PlannedWorkoutStatus
    }

    struct CompletedRun: Equatable, Sendable {
        var id: UUID
        var date: Date
        var distanceMeters: Double
    }

    enum Change: Equatable, Sendable {
        case completed(plannedID: UUID, activityID: UUID)
        case skipped(plannedID: UUID)
    }

    static let dayTolerance = 1
    static let distanceTolerance = 0.25
    static let skipGraceSeconds: TimeInterval = 36 * 3600

    /// A planned workout is `completed` when a run within ±1 calendar day has a
    /// distance within 25% of the estimate (any distance if the estimate is
    /// open/tiny). It becomes `skipped` 36 h past due with no match.
    /// Each activity satisfies at most one planned workout.
    static func evaluate(
        planned: [PlannedSnapshot],
        activities: [CompletedRun],
        now: Date,
        calendar: Calendar = .current
    ) -> [Change] {
        var changes: [Change] = []
        var usedActivityIDs = Set<UUID>()

        for plan in planned.sorted(by: { $0.date < $1.date }) {
            guard plan.status == .pending || plan.status == .scheduledOnWatch else { continue }

            let candidates = activities
                .filter { !usedActivityIDs.contains($0.id) }
                .filter { daysApart(plan.date, $0.date, calendar: calendar) <= dayTolerance }
                .filter { distanceMatches(plan.estimatedDistanceMeters, $0.distanceMeters) }
                .sorted {
                    abs($0.date.timeIntervalSince(plan.date)) < abs($1.date.timeIntervalSince(plan.date))
                }

            if let match = candidates.first {
                usedActivityIDs.insert(match.id)
                changes.append(.completed(plannedID: plan.id, activityID: match.id))
            } else if now.timeIntervalSince(plan.date) > skipGraceSeconds {
                changes.append(.skipped(plannedID: plan.id))
            }
        }
        return changes
    }

    /// Light adaptation trigger: ≥2 skipped sessions in the trailing 7 days.
    static func shouldReduceNextWeek(
        skippedDates: [Date],
        now: Date
    ) -> Bool {
        skippedDates.filter { now.timeIntervalSince($0) <= 7 * 86_400 && $0 <= now }.count >= 2
    }

    // MARK: - Private

    private static func daysApart(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let dayA = calendar.startOfDay(for: a)
        let dayB = calendar.startOfDay(for: b)
        return abs(calendar.dateComponents([.day], from: dayA, to: dayB).day ?? .max)
    }

    private static func distanceMatches(_ estimate: Double, _ actual: Double) -> Bool {
        guard estimate >= 1000 else { return true } // open/unknown target
        return abs(actual - estimate) <= estimate * distanceTolerance
    }
}
