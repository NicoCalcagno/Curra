import Charts
import SwiftData
import SwiftUI

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GoalMaintenanceService.self) private var maintenance
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]

    let goal: Goal

    var body: some View {
        let progress = GoalEngine.progress(
            metric: goal.metric,
            period: goal.period,
            target: goal.targetValue,
            activities: activities.map(\.summary)
        )

        ScrollView {
            VStack(spacing: 24) {
                GoalProgressRing(fraction: progress.fraction, isCompleted: progress.paceStatus == .completed)
                    .frame(width: 160, height: 160)
                    .overlay {
                        VStack {
                            Text(RunFormatters.goalValue(progress.achieved, metric: goal.metric))
                                .font(.largeTitle.weight(.bold))
                                .monospacedDigit()
                            Text("of \(RunFormatters.goalValue(progress.target, metric: goal.metric)) \(goal.metric.unitLabel)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                if !pastPeriods.isEmpty {
                    trendChart
                }
            }
            .padding()
        }
        .navigationTitle("\(goal.period.displayName) \(goal.metric.displayName.lowercased())")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Delete goal", role: .destructive) {
                    modelContext.delete(goal)
                    try? modelContext.save()
                    maintenance.refresh()
                    dismiss()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var pastPeriods: [GoalPeriodRecord] {
        goal.history.sorted { $0.periodStart < $1.periodStart }.suffix(12)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past periods")
                .font(.headline)

            Chart(pastPeriods, id: \.id) { record in
                BarMark(
                    x: .value("Period", record.periodStart, unit: chartUnit),
                    y: .value("Achieved", displayValue(record.achievedValue))
                )
                .foregroundStyle(record.wasCompleted ? Color.green : Color.orange)

                RuleMark(y: .value("Target", displayValue(goal.targetValue)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartUnit: Calendar.Component {
        switch goal.period {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }

    private func displayValue(_ base: Double) -> Double {
        switch goal.metric {
        case .distance: base / 1000
        case .duration: base / 3600
        case .runCount, .elevationGain: base
        }
    }
}
