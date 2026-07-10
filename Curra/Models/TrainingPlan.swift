import Foundation
import SwiftData

/// Multi-week structured plan (Phase 4). Defined now so the SwiftData schema
/// stays frozen after Phase 1.
@Model
final class TrainingPlan {
    var id: UUID
    var name: String
    var raceTypeRaw: String
    var startDate: Date
    var raceDate: Date?
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan)
    var plannedWorkouts: [PlannedWorkout]

    init(
        name: String,
        raceType: RaceType,
        startDate: Date,
        raceDate: Date? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.raceTypeRaw = raceType.rawValue
        self.startDate = startDate
        self.raceDate = raceDate
        self.isActive = true
        self.plannedWorkouts = []
    }

    var raceType: RaceType {
        get { RaceType(rawValue: raceTypeRaw) ?? .tenK }
        set { raceTypeRaw = newValue.rawValue }
    }
}
