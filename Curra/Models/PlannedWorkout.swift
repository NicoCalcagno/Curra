import Foundation
import SwiftData

/// A workout scheduled (or to be scheduled) on the Watch. `id` doubles as the
/// WorkoutKit `WorkoutPlan.id` so scheduled entries can be correlated.
/// The structure is stored as a JSON-encoded `WorkoutBlueprint` — a closed value
/// type we own — because WorkoutKit types are not persistable.
@Model
final class PlannedWorkout {
    var id: UUID
    var scheduledDate: Date
    var blueprintData: Data
    var statusRaw: String
    var matchedActivityID: UUID?
    var plan: TrainingPlan?

    init(scheduledDate: Date, blueprintData: Data, id: UUID = UUID()) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.blueprintData = blueprintData
        self.statusRaw = PlannedWorkoutStatus.pending.rawValue
        self.matchedActivityID = nil
        self.plan = nil
    }

    var status: PlannedWorkoutStatus {
        get { PlannedWorkoutStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
