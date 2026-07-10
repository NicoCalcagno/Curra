import Foundation

enum GoalPaceStatus: String, Equatable, Sendable {
    case completed
    case ahead
    case onTrack
    case behind
}

struct GoalProgress: Equatable, Sendable {
    var periodStart: Date
    var periodEnd: Date
    var achieved: Double
    var target: Double
    var fraction: Double // achieved/target, clamped to 0...1
    var remaining: Double
    var paceStatus: GoalPaceStatus
}

/// Pure goal math: period boundaries, metric aggregation, progress and
/// closed-period enumeration for historicization. No SwiftData, fully testable.
enum GoalEngine {
    static func periodInterval(
        for unit: GoalPeriodUnit,
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        calendar.dateInterval(of: unit.calendarComponent, for: date)
            ?? DateInterval(start: date, duration: 0)
    }

    static func value(of metric: GoalMetric, for activity: ActivitySummary) -> Double {
        switch metric {
        case .distance: activity.distanceMeters
        case .duration: activity.durationSeconds
        case .runCount: 1
        case .elevationGain: activity.elevationGainMeters ?? 0
        }
    }

    /// Sum of `metric` over activities starting in `[interval.start, interval.end)`.
    static func aggregate(
        _ metric: GoalMetric,
        activities: [ActivitySummary],
        in interval: DateInterval
    ) -> Double {
        activities
            .filter { $0.startDate >= interval.start && $0.startDate < interval.end }
            .reduce(0) { $0 + value(of: metric, for: $1) }
    }

    static func progress(
        metric: GoalMetric,
        period: GoalPeriodUnit,
        target: Double,
        activities: [ActivitySummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalProgress {
        let interval = periodInterval(for: period, containing: now, calendar: calendar)
        let achieved = aggregate(metric, activities: activities, in: interval)
        let achievedFraction = target > 0 ? achieved / target : 0
        let elapsedFraction = interval.duration > 0
            ? min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
            : 1

        let status: GoalPaceStatus
        if target > 0, achieved >= target {
            status = .completed
        } else if achievedFraction >= elapsedFraction {
            status = .ahead
        } else if achievedFraction + 0.1 >= elapsedFraction {
            status = .onTrack
        } else {
            status = .behind
        }

        return GoalProgress(
            periodStart: interval.start,
            periodEnd: interval.end,
            achieved: achieved,
            target: target,
            fraction: min(1, max(0, achievedFraction)),
            remaining: max(0, target - achieved),
            paceStatus: status
        )
    }

    /// Fully-elapsed period intervals that overlap `[creation, now)`, most recent
    /// first, capped at `limit`. Used to backfill `GoalPeriodRecord`s.
    static func closedPeriods(
        for unit: GoalPeriodUnit,
        from creation: Date,
        until now: Date,
        calendar: Calendar = .current,
        limit: Int = 26
    ) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursorEnd = periodInterval(for: unit, containing: now, calendar: calendar).start

        while result.count < limit, cursorEnd > creation {
            let interval = periodInterval(
                for: unit,
                containing: cursorEnd.addingTimeInterval(-1),
                calendar: calendar
            )
            result.append(interval)
            cursorEnd = interval.start
        }
        return result
    }
}
