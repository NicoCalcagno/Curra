import Foundation

struct PlannedWorkoutSpec: Equatable, Sendable {
    var date: Date
    var blueprint: WorkoutBlueprint
}

/// Pure plan generation: template + start date + current load → dated blueprints.
enum PlanEngine {
    /// Weekly volume progression: ≤ +10% per week toward the peak, every 4th
    /// week is a cutback (×0.7), the final (race) week tapers (×0.6).
    static func weeklyVolumes(startKm: Double, peakKm: Double, weeks: Int) -> [Double] {
        guard weeks > 0 else { return [] }
        var volumes: [Double] = []
        var base = min(startKm, peakKm)

        for index in 0..<weeks {
            if index == weeks - 1 {
                volumes.append(base * 0.6) // taper
            } else if (index + 1) % 4 == 0 {
                volumes.append(base * 0.7) // cutback, base keeps its value
            } else {
                if index > 0 {
                    base = min(base * 1.1, peakKm)
                }
                volumes.append(base)
            }
        }
        return volumes
    }

    /// Share of the weekly volume assigned to each session kind.
    static func distanceShares(for sessions: [PlanTemplate.SessionSlot]) -> [Double] {
        let easyCount = Double(sessions.filter { $0.kind == .easy }.count)
        let longShare = 0.40
        let qualityShare = 0.25
        let easyTotal = 1.0 - longShare - qualityShare

        return sessions.map { slot in
            switch slot.kind {
            case .long: longShare
            case .quality: qualityShare
            case .easy: easyCount > 0 ? easyTotal / easyCount : 0
            }
        }
    }

    /// `startDate` must be the first day of week 1 (the UI passes next Monday).
    static func generate(
        template: PlanTemplate,
        startDate: Date,
        load: TrainingLoad,
        calendar: Calendar = .current
    ) -> [PlannedWorkoutSpec] {
        let startKm = max(template.minStartWeeklyKm, min(load.weeklyKilometers, template.peakWeeklyKm))
        let volumes = weeklyVolumes(
            startKm: startKm,
            peakKm: template.peakWeeklyKm,
            weeks: template.weekCount
        )
        let shares = distanceShares(for: template.sessions)

        var specs: [PlannedWorkoutSpec] = []
        for (weekIndex, weekKm) in volumes.enumerated() {
            for (slotIndex, slot) in template.sessions.enumerated() {
                guard let day = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + slot.dayOffset,
                    to: startDate
                ) else { continue }
                let date = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day

                let sessionKm = (weekKm * shares[slotIndex] * 2).rounded() / 2 // 0.5 km steps
                specs.append(
                    PlannedWorkoutSpec(
                        date: date,
                        blueprint: blueprint(
                            for: slot.kind,
                            kilometers: sessionKm,
                            weekIndex: weekIndex,
                            weekKm: weekKm,
                            load: load
                        )
                    )
                )
            }
        }
        return specs
    }

    // MARK: - Session blueprints

    static func blueprint(
        for kind: SessionKind,
        kilometers: Double,
        weekIndex: Int,
        weekKm: Double,
        load: TrainingLoad
    ) -> WorkoutBlueprint {
        switch kind {
        case .easy:
            return distanceRun(
                name: String(format: "Easy run — %.1f km", kilometers),
                mode: .maintain,
                kilometers: kilometers,
                zone: 2,
                label: "easy, HR zone 2"
            )
        case .long:
            return distanceRun(
                name: String(format: "Long run — %.1f km", kilometers),
                mode: .maintain,
                kilometers: kilometers,
                zone: 2,
                label: "long run, HR zone 2"
            )
        case .quality:
            // Reuse the instant-workout Build generator, parametrized by this
            // plan week's volume; the variant rotates the session type weekly.
            var weekLoad = load
            weekLoad.weeklyKilometers = weekKm
            weekLoad.daysSinceLastRun = 1
            return InstantWorkoutGenerator.workout(mode: .build, load: weekLoad, variant: weekIndex)
        }
    }

    private static func distanceRun(
        name: String,
        mode: WorkoutMode,
        kilometers: Double,
        zone: Int,
        label: String
    ) -> WorkoutBlueprint {
        let step = StepBlueprint(
            purpose: .work,
            goal: .distanceMeters(kilometers * 1000),
            alert: .heartRateZone(zone),
            label: String(format: "%.1f km %@", kilometers, label)
        )
        return WorkoutBlueprint(
            name: name,
            mode: mode,
            warmup: nil,
            blocks: [BlockBlueprint(steps: [step], iterations: 1)],
            cooldown: nil
        )
    }

    /// Scales every distance/duration goal (used by the light adaptation when
    /// sessions get skipped). Distances round to 100 m, times to whole minutes.
    static func scaled(_ blueprint: WorkoutBlueprint, factor: Double) -> WorkoutBlueprint {
        var result = blueprint
        result.warmup = blueprint.warmup.map { scaledStep($0, factor: factor) }
        result.cooldown = blueprint.cooldown.map { scaledStep($0, factor: factor) }
        result.blocks = blueprint.blocks.map { block in
            BlockBlueprint(
                steps: block.steps.map { scaledStep($0, factor: factor) },
                iterations: block.iterations
            )
        }
        return result
    }

    private static func scaledStep(_ step: StepBlueprint, factor: Double) -> StepBlueprint {
        var result = step
        switch step.goal {
        case .open:
            break
        case .distanceMeters(let meters):
            result.goal = .distanceMeters(((meters * factor) / 100).rounded() * 100)
        case .durationSeconds(let seconds):
            result.goal = .durationSeconds(((seconds * factor) / 60).rounded() * 60)
        }
        return result
    }
}
