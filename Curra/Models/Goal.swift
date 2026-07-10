import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var metricRaw: String
    var periodRaw: String
    var targetValue: Double
    var createdAt: Date
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \GoalPeriodRecord.goal)
    var history: [GoalPeriodRecord]

    init(
        metric: GoalMetric,
        period: GoalPeriodUnit,
        targetValue: Double,
        createdAt: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.metricRaw = metric.rawValue
        self.periodRaw = period.rawValue
        self.targetValue = targetValue
        self.createdAt = createdAt
        self.isActive = true
        self.history = []
    }

    var metric: GoalMetric {
        get { GoalMetric(rawValue: metricRaw) ?? .distance }
        set { metricRaw = newValue.rawValue }
    }

    var period: GoalPeriodUnit {
        get { GoalPeriodUnit(rawValue: periodRaw) ?? .weekly }
        set { periodRaw = newValue.rawValue }
    }
}

/// Snapshot of a closed goal period, written once by `GoalHistoryService`.
@Model
final class GoalPeriodRecord {
    var id: UUID
    var periodStart: Date
    var periodEnd: Date
    var achievedValue: Double
    var targetValue: Double
    var wasCompleted: Bool
    var goal: Goal?

    init(
        periodStart: Date,
        periodEnd: Date,
        achievedValue: Double,
        targetValue: Double,
        id: UUID = UUID()
    ) {
        self.id = id
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.achievedValue = achievedValue
        self.targetValue = targetValue
        self.wasCompleted = achievedValue >= targetValue
        self.goal = nil
    }
}
