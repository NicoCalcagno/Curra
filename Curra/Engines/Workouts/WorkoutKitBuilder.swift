import Foundation
import HealthKit
import WorkoutKit

/// The ONLY place that touches WorkoutKit's workout-construction types.
/// If an API name drifted between SDK versions, the fix is confined here.
enum WorkoutKitBuilder {
    static func customWorkout(from blueprint: WorkoutBlueprint) -> CustomWorkout {
        CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: blueprint.name,
            warmup: blueprint.warmup.map(workoutStep),
            blocks: blueprint.blocks.map(intervalBlock),
            cooldown: blueprint.cooldown.map(workoutStep)
        )
    }

    // MARK: - Steps

    private static func workoutStep(_ step: StepBlueprint) -> WorkoutStep {
        WorkoutStep(goal: goal(step.goal), alert: alert(step.alert))
    }

    private static func intervalBlock(_ block: BlockBlueprint) -> IntervalBlock {
        // WorkoutKit supports fixed iteration counts only.
        IntervalBlock(steps: block.steps.map(intervalStep), iterations: max(1, block.iterations))
    }

    private static func intervalStep(_ step: StepBlueprint) -> IntervalStep {
        IntervalStep(
            step.purpose == .work ? .work : .recovery,
            goal: goal(step.goal),
            alert: alert(step.alert)
        )
    }

    // MARK: - Goals

    private static func goal(_ stepGoal: StepGoal) -> WorkoutGoal {
        switch stepGoal {
        case .open:
            .open
        case .distanceMeters(let meters):
            .distance(meters, .meters)
        case .durationSeconds(let seconds):
            .time(seconds, .seconds)
        }
    }

    // MARK: - Alerts (reactive only — WorkoutKit has no pre-step warnings)

    private static func alert(_ stepAlert: StepAlert?) -> (any WorkoutAlert)? {
        switch stepAlert {
        case nil:
            return nil
        case .heartRateZone(let zone):
            return HeartRateZoneAlert(zone: zone)
        case .paceRange(let minSecondsPerKm, let maxSecondsPerKm):
            // Pace (sec/km) → speed (m/s): the slower pace bounds the lower speed.
            let slow = Measurement(value: 1000 / maxSecondsPerKm, unit: UnitSpeed.metersPerSecond)
            let fast = Measurement(value: 1000 / minSecondsPerKm, unit: UnitSpeed.metersPerSecond)
            return SpeedRangeAlert(target: slow...fast, metric: .current)
        }
    }
}
