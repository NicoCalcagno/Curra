import SwiftData
import SwiftUI
import WorkoutKit

struct InstantWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]

    @State private var scheduler = WorkoutSchedulerService()
    @State private var selectedMode: WorkoutMode?
    @State private var variant = 0
    @State private var scheduleDate = Self.defaultScheduleDate()
    @State private var isShowingPreview = false
    @State private var feedback: String?

    private var load: TrainingLoad {
        TrainingLoadCalculator.load(from: activities.map(\.summary))
    }

    private var blueprint: WorkoutBlueprint? {
        selectedMode.map { InstantWorkoutGenerator.workout(mode: $0, load: load, variant: variant) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    suggestionBanner

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(WorkoutMode.allCases, id: \.self) { mode in
                            modeCard(mode)
                        }
                    }

                    if let blueprint {
                        WorkoutPreviewCard(
                            blueprint: blueprint,
                            referencePace: load.typicalEasyPaceSecPerKm
                        )
                        actions(for: blueprint)
                    }

                    if !scheduler.isAuthorized {
                        authorizationSection
                    }

                    if let feedback {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Workouts")
            .task {
                await scheduler.refreshAuthorization()
            }
        }
    }

    // MARK: - Sections

    private var suggestionBanner: some View {
        let suggested = TrainingLoadCalculator.suggestedMode(for: load)
        return HStack(spacing: 12) {
            Image(systemName: suggested.systemImage)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's suggestion: \(suggested.displayName)")
                    .font(.headline)
                Text(suggested.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            selectedMode = suggested
        }
    }

    private func modeCard(_ mode: WorkoutMode) -> some View {
        Button {
            if selectedMode == mode {
                variant += 1 // tapping again rotates Build variants
            } else {
                selectedMode = mode
                variant = 0
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.title3)
                Text(mode.displayName)
                    .font(.headline)
                Text(mode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                selectedMode == mode ? .orange.opacity(0.2) : .quaternary.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func actions(for blueprint: WorkoutBlueprint) -> some View {
        VStack(spacing: 12) {
            DatePicker(
                "Schedule for",
                selection: $scheduleDate,
                in: Date.now...Date.now.addingTimeInterval(7 * 86_400) // WorkoutKit window
            )

            HStack {
                Button {
                    isShowingPreview = true
                } label: {
                    Label("Start now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .workoutPreview(scheduler.previewPlan(for: blueprint), isPresented: $isShowingPreview)

                Button {
                    sendToWatch(blueprint)
                } label: {
                    Label("Send to Watch", systemImage: "applewatch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!scheduler.isAuthorized)
            }
        }
    }

    private var authorizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow Curra to schedule workouts so they appear in the Watch's Workout app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Allow workout scheduling") {
                Task { await scheduler.requestAuthorization() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func sendToWatch(_ blueprint: WorkoutBlueprint) {
        feedback = nil
        Task {
            do {
                try await scheduler.schedule(blueprint, at: scheduleDate, in: modelContext)
                feedback = "“\(blueprint.name)” scheduled — it will appear in the Watch's Workout app."
            } catch {
                feedback = "Scheduling failed: \(error.localizedDescription)"
            }
        }
    }

    private static func defaultScheduleDate() -> Date {
        // Next full hour, a sane default for "today's run".
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }
}
