import Foundation

/// Value-type description of a structured workout. This is what we persist
/// (JSON in `PlannedWorkout.blueprintData`), generate, and unit-test; WorkoutKit
/// types are produced from it only at scheduling time (`WorkoutKitBuilder`).
enum WorkoutMode: String, Codable, CaseIterable, Sendable {
    case maintain
    case build
    case explore
    case recover

    var displayName: String {
        switch self {
        case .maintain: "Maintain"
        case .build: "Build"
        case .explore: "Explore"
        case .recover: "Recover"
        }
    }

    var subtitle: String {
        switch self {
        case .maintain: "Steady run in your easy heart-rate zone"
        case .build: "Intervals or tempo to push your fitness"
        case .explore: "Open run — go where your legs take you"
        case .recover: "Short and slow to absorb training"
        }
    }

    var systemImage: String {
        switch self {
        case .maintain: "figure.run"
        case .build: "flame"
        case .explore: "map"
        case .recover: "leaf"
        }
    }
}

enum StepPurpose: String, Codable, Equatable, Sendable {
    case work
    case recovery
}

enum StepGoal: Codable, Equatable, Sendable {
    case open
    case distanceMeters(Double)
    case durationSeconds(Double)
}

enum StepAlert: Codable, Equatable, Sendable {
    case heartRateZone(Int)
    case paceRange(minSecondsPerKm: Double, maxSecondsPerKm: Double)
}

struct StepBlueprint: Codable, Equatable, Sendable {
    var purpose: StepPurpose
    var goal: StepGoal
    var alert: StepAlert?
    var label: String
}

struct BlockBlueprint: Codable, Equatable, Sendable {
    // WorkoutKit `IntervalBlock` supports fixed iteration counts only —
    // no "repeat until cumulative distance". Honored, not worked around.
    var steps: [StepBlueprint]
    var iterations: Int
}

struct WorkoutBlueprint: Codable, Equatable, Sendable {
    var name: String
    var mode: WorkoutMode
    var warmup: StepBlueprint?
    var blocks: [BlockBlueprint]
    var cooldown: StepBlueprint?

    /// All steps in execution order with block iterations expanded.
    var expandedSteps: [StepBlueprint] {
        var steps: [StepBlueprint] = []
        if let warmup { steps.append(warmup) }
        for block in blocks {
            for _ in 0..<max(1, block.iterations) {
                steps.append(contentsOf: block.steps)
            }
        }
        if let cooldown { steps.append(cooldown) }
        return steps
    }

    /// Rough duration for the UI. Distance steps are converted with the step's
    /// pace-alert midpoint when present, else `referencePaceSecPerKm`.
    func estimatedDurationSeconds(referencePaceSecPerKm: Double) -> Double {
        expandedSteps.reduce(0) { total, step in
            switch step.goal {
            case .open:
                total
            case .durationSeconds(let seconds):
                total + seconds
            case .distanceMeters(let meters):
                total + meters / 1000 * pace(for: step, fallback: referencePaceSecPerKm)
            }
        }
    }

    /// Rough distance for the UI (open steps contribute nothing).
    func estimatedDistanceMeters(referencePaceSecPerKm: Double) -> Double {
        expandedSteps.reduce(0) { total, step in
            switch step.goal {
            case .open:
                total
            case .distanceMeters(let meters):
                total + meters
            case .durationSeconds(let seconds):
                total + seconds / pace(for: step, fallback: referencePaceSecPerKm) * 1000
            }
        }
    }

    private func pace(for step: StepBlueprint, fallback: Double) -> Double {
        if case .paceRange(let minPace, let maxPace) = step.alert {
            return (minPace + maxPace) / 2
        }
        return fallback
    }

    // MARK: - Persistence helpers

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> WorkoutBlueprint {
        try JSONDecoder().decode(WorkoutBlueprint.self, from: data)
    }
}
