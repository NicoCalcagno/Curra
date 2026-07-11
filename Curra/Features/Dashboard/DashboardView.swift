import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(filter: #Predicate<Goal> { $0.isActive }, sort: \Goal.createdAt)
    private var goals: [Goal]
    @Query(sort: \Activity.startDate, order: .reverse)
    private var activities: [Activity]

    @State private var isAddingGoal = false

    private var summaries: [ActivitySummary] { activities.map(\.summary) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    weekSummary

                    if goals.isEmpty {
                        ContentUnavailableView(
                            "No goals yet",
                            systemImage: "target",
                            description: Text("Create a goal like “40 km per week” and track it here and in the widget.")
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                            ForEach(goals) { goal in
                                NavigationLink {
                                    GoalDetailView(goal: goal)
                                } label: {
                                    GoalCard(goal: goal, summaries: summaries)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let latest = activities.first {
                        lastRunCard(latest)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingGoal) {
                GoalEditorView()
            }
        }
    }

    private var weekSummary: some View {
        let interval = GoalEngine.periodInterval(for: .weekly, containing: .now)
        let distance = GoalEngine.aggregate(.distance, activities: summaries, in: interval)
        let duration = GoalEngine.aggregate(.duration, activities: summaries, in: interval)
        let runs = GoalEngine.aggregate(.runCount, activities: summaries, in: interval)

        return HStack(spacing: 0) {
            summaryItem(RunFormatters.distance(distance), "This week")
            Divider().frame(height: 32)
            summaryItem(RunFormatters.duration(duration), "Time")
            Divider().frame(height: 32)
            summaryItem("\(Int(runs))", "Runs")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func lastRunCard(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last run").font(.caption).foregroundStyle(.secondary)
            Text(activity.name).font(.headline)
            HStack(spacing: 12) {
                Text(activity.startDate, format: .dateTime.weekday(.wide).day().month())
                Text(RunFormatters.distance(activity.distanceMeters))
                Text(RunFormatters.pace(secondsPerKm: activity.paceSecondsPerKm))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GoalCard: View {
    let goal: Goal
    let summaries: [ActivitySummary]

    var body: some View {
        let progress = GoalEngine.progress(
            metric: goal.metric,
            period: goal.period,
            target: goal.targetValue,
            activities: summaries
        )

        VStack(spacing: 10) {
            GoalProgressRing(fraction: progress.fraction, isCompleted: progress.paceStatus == .completed)
                .frame(width: 88, height: 88)
                .overlay {
                    VStack(spacing: 0) {
                        Text(RunFormatters.goalValue(progress.achieved, metric: goal.metric))
                            .font(.headline)
                            .monospacedDigit()
                        Text(goal.metric.unitLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

            VStack(spacing: 2) {
                Text("\(goal.period.displayName) \(goal.metric.displayName.lowercased())")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(statusLabel(progress.paceStatus))
                    .font(.caption)
                    .foregroundStyle(statusColor(progress.paceStatus))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusLabel(_ status: GoalPaceStatus) -> String {
        switch status {
        case .completed: "Completed"
        case .ahead: "Ahead of pace"
        case .onTrack: "On track"
        case .behind: "Behind pace"
        }
    }

    private func statusColor(_ status: GoalPaceStatus) -> Color {
        switch status {
        case .completed: .green
        case .ahead: .green
        case .onTrack: .secondary
        case .behind: .orange
        }
    }
}
