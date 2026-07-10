import Foundation
import SwiftData
import WidgetKit

/// Housekeeping that runs at launch, on app foreground, and after every data
/// change: backfills closed-period history records and refreshes the widget
/// snapshot. Idempotent by construction.
@MainActor
@Observable
final class GoalMaintenanceService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh(now: Date = .now) {
        let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        let activities = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []
        let summaries = activities.map(\.summary)

        historicizeClosedPeriods(goals: goals.filter(\.isActive), summaries: summaries, now: now)
        publishWidgetSnapshot(goals: goals.filter(\.isActive), summaries: summaries, now: now)
    }

    // MARK: - History

    private func historicizeClosedPeriods(
        goals: [Goal],
        summaries: [ActivitySummary],
        now: Date
    ) {
        var changed = false
        for goal in goals {
            let recorded = Set(goal.history.map(\.periodStart))
            let missing = GoalEngine.closedPeriods(for: goal.period, from: goal.createdAt, until: now)
                .filter { !recorded.contains($0.start) }

            for interval in missing {
                let achieved = GoalEngine.aggregate(goal.metric, activities: summaries, in: interval)
                let record = GoalPeriodRecord(
                    periodStart: interval.start,
                    periodEnd: interval.end,
                    achievedValue: achieved,
                    targetValue: goal.targetValue
                )
                modelContext.insert(record)
                record.goal = goal
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
    }

    // MARK: - Widget snapshot

    private func publishWidgetSnapshot(
        goals: [Goal],
        summaries: [ActivitySummary],
        now: Date
    ) {
        // Prefer a weekly goal (the widget's headline use case), else any active one.
        guard let goal = goals.first(where: { $0.period == .weekly }) ?? goals.first else {
            GoalSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let progress = GoalEngine.progress(
            metric: goal.metric,
            period: goal.period,
            target: goal.targetValue,
            activities: summaries,
            now: now
        )

        let achieved = RunFormatters.goalValue(progress.achieved, metric: goal.metric)
        let target = RunFormatters.goalValue(progress.target, metric: goal.metric)
        let remaining = RunFormatters.goalValue(progress.remaining, metric: goal.metric)
        let unit = goal.metric.unitLabel

        GoalSnapshot(
            title: "\(goal.period.displayName) \(goal.metric.displayName.lowercased())",
            valueLabel: "\(achieved) of \(target) \(unit)",
            detailLabel: progress.paceStatus == .completed
                ? "Completed 🎉"
                : "\(remaining) \(unit) to go",
            fraction: progress.fraction,
            isCompleted: progress.paceStatus == .completed,
            periodEnd: progress.periodEnd,
            updatedAt: now
        ).save()

        WidgetCenter.shared.reloadAllTimelines()
    }
}
