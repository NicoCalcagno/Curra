import Foundation
import SwiftData
import WorkoutKit

/// Sends blueprints to the Watch's native Workout app via `WorkoutScheduler`
/// and records a `PlannedWorkout` for each scheduled entry.
/// Constraint honored: scheduled workouts are only visible in a ±7-day window.
@MainActor
@Observable
final class WorkoutSchedulerService {
    private(set) var isAuthorized = false

    func refreshAuthorization() async {
        isAuthorized = await WorkoutScheduler.shared.authorizationState == .authorized
    }

    func requestAuthorization() async {
        let state = await WorkoutScheduler.shared.requestAuthorization()
        isAuthorized = state == .authorized
    }

    /// Schedules on the Watch and persists the planned workout.
    /// `PlannedWorkout.id` is reused as the `WorkoutPlan` id for correlation.
    func schedule(
        _ blueprint: WorkoutBlueprint,
        at date: Date,
        in modelContext: ModelContext
    ) async throws {
        let planned = PlannedWorkout(scheduledDate: date, blueprintData: try blueprint.encoded())
        let workoutPlan = WorkoutPlan(
            .custom(WorkoutKitBuilder.customWorkout(from: blueprint)),
            id: planned.id
        )

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        await WorkoutScheduler.shared.schedule(workoutPlan, at: components)

        planned.status = .scheduledOnWatch
        modelContext.insert(planned)
        try modelContext.save()
    }

    /// A `WorkoutPlan` ready for the system preview sheet (start-now flow).
    func previewPlan(for blueprint: WorkoutBlueprint) -> WorkoutPlan {
        WorkoutPlan(.custom(WorkoutKitBuilder.customWorkout(from: blueprint)))
    }

    func removeFromWatch(_ planned: PlannedWorkout) async {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: planned.scheduledDate
        )
        let blueprint = try? WorkoutBlueprint.decoded(from: planned.blueprintData)
        guard let blueprint else { return }
        let workoutPlan = WorkoutPlan(
            .custom(WorkoutKitBuilder.customWorkout(from: blueprint)),
            id: planned.id
        )
        await WorkoutScheduler.shared.remove(workoutPlan, at: components)
    }
}
