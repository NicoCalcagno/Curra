import Foundation

/// Deterministic workout generation: (mode, load, variant) → blueprint.
/// Pure function so structure invariants are unit-testable. `variant` rotates
/// Build session types; other modes ignore it.
enum InstantWorkoutGenerator {
    static func workout(mode: WorkoutMode, load: TrainingLoad, variant: Int = 0) -> WorkoutBlueprint {
        switch mode {
        case .maintain: maintain(load)
        case .build: build(load, variant: variant)
        case .explore: explore(load)
        case .recover: recover(load)
        }
    }

    // MARK: - Maintain: steady aerobic run

    private static func maintain(_ load: TrainingLoad) -> WorkoutBlueprint {
        let minutes = clamp(load.weeklyKilometers * 1.8, 30, 60).rounded(toMultipleOf: 5)
        let steady = StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(minutes * 60),
            alert: .heartRateZone(2),
            label: "\(Int(minutes)) min steady, HR zone 2"
        )
        return WorkoutBlueprint(
            name: "Maintain — \(Int(minutes)) min steady",
            mode: .maintain,
            warmup: warmupStep(minutes: 10),
            blocks: [BlockBlueprint(steps: [steady], iterations: 1)],
            cooldown: cooldownStep(minutes: 5)
        )
    }

    // MARK: - Build: quality session (3 rotating variants)

    private static func build(_ load: TrainingLoad, variant: Int) -> WorkoutBlueprint {
        let lowVolume = load.weeklyKilometers < 8
        let rusty = (load.daysSinceLastRun ?? 0) >= 7

        switch ((variant % 3) + 3) % 3 {
        case 0: return intervals800(load, reduced: lowVolume || rusty)
        case 1: return tempo(load, reduced: lowVolume || rusty)
        default: return shortIntervals(load, reduced: lowVolume || rusty)
        }
    }

    private static func intervals800(_ load: TrainingLoad, reduced: Bool) -> WorkoutBlueprint {
        var reps = Int(clamp(load.weeklyKilometers / 8, 3, 8))
        if reduced { reps = max(3, Int(Double(reps) * 0.6)) }

        let fiveK = load.estimated5KPaceSecPerKm
        let work = StepBlueprint(
            purpose: .work,
            goal: .distanceMeters(800),
            alert: .paceRange(minSecondsPerKm: fiveK - 10, maxSecondsPerKm: fiveK + 10),
            label: "800 m @ 5K pace"
        )
        let recovery = StepBlueprint(
            purpose: .recovery,
            goal: .distanceMeters(400),
            alert: .heartRateZone(1),
            label: "400 m easy recovery"
        )
        return WorkoutBlueprint(
            name: "Build — \(reps)×800 m",
            mode: .build,
            warmup: warmupStep(minutes: 10),
            blocks: [BlockBlueprint(steps: [work, recovery], iterations: reps)],
            cooldown: cooldownStep(minutes: 10)
        )
    }

    private static func tempo(_ load: TrainingLoad, reduced: Bool) -> WorkoutBlueprint {
        var minutes = clamp(20 + load.weeklyKilometers / 4, 20, 35).rounded(toMultipleOf: 5)
        if reduced { minutes = 20 }

        let easy = load.typicalEasyPaceSecPerKm
        let work = StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(minutes * 60),
            alert: .paceRange(minSecondsPerKm: easy - 50, maxSecondsPerKm: easy - 35),
            label: "\(Int(minutes)) min tempo"
        )
        return WorkoutBlueprint(
            name: "Build — \(Int(minutes)) min tempo",
            mode: .build,
            warmup: warmupStep(minutes: 10),
            blocks: [BlockBlueprint(steps: [work], iterations: 1)],
            cooldown: cooldownStep(minutes: 5)
        )
    }

    private static func shortIntervals(_ load: TrainingLoad, reduced: Bool) -> WorkoutBlueprint {
        var reps = Int(clamp(load.weeklyKilometers / 5, 6, 10))
        if reduced { reps = 6 }

        let fiveK = load.estimated5KPaceSecPerKm
        let work = StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(60),
            alert: .paceRange(minSecondsPerKm: fiveK - 15, maxSecondsPerKm: fiveK),
            label: "1 min hard"
        )
        let recovery = StepBlueprint(
            purpose: .recovery,
            goal: .durationSeconds(60),
            alert: .heartRateZone(1),
            label: "1 min easy"
        )
        return WorkoutBlueprint(
            name: "Build — \(reps)×1 min",
            mode: .build,
            warmup: warmupStep(minutes: 10),
            blocks: [BlockBlueprint(steps: [work, recovery], iterations: reps)],
            cooldown: cooldownStep(minutes: 5)
        )
    }

    // MARK: - Explore: open run

    private static func explore(_ load: TrainingLoad) -> WorkoutBlueprint {
        let targetKm = (load.longestRecentRunKm * 0.8).rounded(toMultipleOf: 0.5)
        let step: StepBlueprint
        if targetKm >= 3 {
            step = StepBlueprint(
                purpose: .work,
                goal: .distanceMeters(targetKm * 1000),
                alert: .heartRateZone(2),
                label: String(format: "%.1f km at a comfortable effort", targetKm)
            )
        } else {
            step = StepBlueprint(
                purpose: .work,
                goal: .open,
                alert: .heartRateZone(2),
                label: "Open run — stop whenever you like"
            )
        }
        return WorkoutBlueprint(
            name: targetKm >= 3
                ? String(format: "Explore — %.1f km", targetKm)
                : "Explore — open run",
            mode: .explore,
            warmup: nil,
            blocks: [BlockBlueprint(steps: [step], iterations: 1)],
            cooldown: nil
        )
    }

    // MARK: - Recover: short and slow

    private static func recover(_ load: TrainingLoad) -> WorkoutBlueprint {
        let minutes: Double = (load.daysSinceLastRun ?? 2) <= 1 ? 20 : 30
        let easy = load.typicalEasyPaceSecPerKm
        let step = StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(minutes * 60),
            alert: .paceRange(minSecondsPerKm: easy + 30, maxSecondsPerKm: easy + 90),
            label: "\(Int(minutes)) min very easy"
        )
        return WorkoutBlueprint(
            name: "Recover — \(Int(minutes)) min easy",
            mode: .recover,
            warmup: nil,
            blocks: [BlockBlueprint(steps: [step], iterations: 1)],
            cooldown: nil
        )
    }

    // MARK: - Shared pieces

    private static func warmupStep(minutes: Double) -> StepBlueprint {
        StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(minutes * 60),
            alert: .heartRateZone(1),
            label: "\(Int(minutes)) min warmup"
        )
    }

    private static func cooldownStep(minutes: Double) -> StepBlueprint {
        StepBlueprint(
            purpose: .work,
            goal: .durationSeconds(minutes * 60),
            alert: nil,
            label: "\(Int(minutes)) min cooldown"
        )
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}

private extension Double {
    func rounded(toMultipleOf multiple: Double) -> Double {
        (self / multiple).rounded() * multiple
    }
}
