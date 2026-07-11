import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(TrainingPlanService.self) private var planService
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive })
    private var activePlans: [TrainingPlan]

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlans.first {
                    ActivePlanView(plan: plan)
                } else {
                    TemplatePickerView()
                }
            }
            .navigationTitle("Plan")
            .task {
                await planService.refresh()
            }
        }
    }
}

// MARK: - Template picker

private struct TemplatePickerView: View {
    @Environment(TrainingPlanService.self) private var planService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a goal race — the plan starts next Monday, anchored to your current weekly volume, and each day's workout lands on your Watch automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(RaceType.allCases, id: \.self) { raceType in
                    templateCard(raceType)
                }
            }
            .padding()
        }
    }

    private func templateCard(_ raceType: RaceType) -> some View {
        let template = PlanTemplate.template(for: raceType)
        return Button {
            planService.createPlan(raceType: raceType)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(raceType.displayName)
                    .font(.title3.weight(.semibold))
                Text("\(template.weekCount) weeks · \(template.sessions.count) sessions/week · peaks at \(Int(template.peakWeeklyKm)) km/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active plan

private struct ActivePlanView: View {
    @Environment(TrainingPlanService.self) private var planService
    let plan: TrainingPlan

    var body: some View {
        List {
            Section {
                header
            }

            ForEach(weeks, id: \.index) { week in
                Section("Week \(week.index + 1)") {
                    ForEach(week.workouts, id: \.id) { planned in
                        PlannedWorkoutRow(planned: planned)
                    }
                }
            }
        }
        .toolbar {
            Menu {
                Button("Cancel plan", role: .destructive) {
                    Task { await planService.cancelPlan(plan) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var header: some View {
        let total = plan.plannedWorkouts.count
        let completed = plan.plannedWorkouts.filter { $0.status == .completed }.count
        let currentWeek = weekIndex(for: .now) + 1

        return VStack(alignment: .leading, spacing: 6) {
            Text(plan.name).font(.headline)
            Text("Week \(min(max(currentWeek, 1), weeks.count)) of \(weeks.count) · \(completed)/\(total) sessions done")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                .tint(.orange)
        }
        .padding(.vertical, 4)
    }

    private struct Week {
        var index: Int
        var workouts: [PlannedWorkout]
    }

    private var weeks: [Week] {
        let grouped = Dictionary(grouping: plan.plannedWorkouts) { weekIndex(for: $0.scheduledDate) }
        return grouped.keys.sorted().map { index in
            Week(index: index, workouts: grouped[index]!.sorted { $0.scheduledDate < $1.scheduledDate })
        }
    }

    private func weekIndex(for date: Date) -> Int {
        Int(date.timeIntervalSince(plan.startDate) / (7 * 86_400))
    }
}

private struct PlannedWorkoutRow: View {
    let planned: PlannedWorkout

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutName)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(planned.status == .skipped)
                Text(planned.scheduledDate, format: .dateTime.weekday(.wide).day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workoutName: String {
        (try? WorkoutBlueprint.decoded(from: planned.blueprintData))?.name ?? "Workout"
    }

    @ViewBuilder private var statusIcon: some View {
        switch planned.status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .scheduledOnWatch:
            Image(systemName: "applewatch").foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "xmark.circle").foregroundStyle(.orange)
        }
    }
}
