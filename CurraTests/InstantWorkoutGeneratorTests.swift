import XCTest
@testable import Curra

final class InstantWorkoutGeneratorTests: XCTestCase {
    private var typicalLoad: TrainingLoad {
        TrainingLoad(
            weeklyKilometers: 40,
            runCount7d: 4,
            daysSinceLastRun: 1,
            typicalEasyPaceSecPerKm: 360,
            estimated5KPaceSecPerKm: 300,
            longestRecentRunKm: 14,
            lastRunWasQuality: false
        )
    }

    private var lowLoad: TrainingLoad {
        TrainingLoad(
            weeklyKilometers: 5,
            runCount7d: 1,
            daysSinceLastRun: 8,
            typicalEasyPaceSecPerKm: 400,
            estimated5KPaceSecPerKm: 350,
            longestRecentRunKm: 3,
            lastRunWasQuality: false
        )
    }

    // MARK: - Structure invariants

    func testMaintainHasWarmupSteadyAndCooldown() {
        let workout = InstantWorkoutGenerator.workout(mode: .maintain, load: typicalLoad)
        XCTAssertNotNil(workout.warmup)
        XCTAssertNotNil(workout.cooldown)
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].steps[0].alert, .heartRateZone(2))

        guard case .durationSeconds(let seconds) = workout.blocks[0].steps[0].goal else {
            return XCTFail("Maintain steady step must be time-based")
        }
        XCTAssertGreaterThanOrEqual(seconds, 30 * 60)
        XCTAssertLessThanOrEqual(seconds, 60 * 60)
        XCTAssertEqual(seconds.truncatingRemainder(dividingBy: 300), 0, "rounded to 5 min")
    }

    func testBuildIntervalsScaleWithVolumeAndClamp() {
        let workout = InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 0)
        let block = workout.blocks[0]
        XCTAssertEqual(block.iterations, 5) // 40 km/week / 8
        XCTAssertEqual(block.steps.count, 2)
        XCTAssertEqual(block.steps[0].purpose, .work)
        XCTAssertEqual(block.steps[1].purpose, .recovery)
        XCTAssertNotNil(block.steps[1].alert, "recovery steps carry an alert")

        guard case .paceRange(let minPace, let maxPace) = block.steps[0].alert else {
            return XCTFail("interval work step needs a pace alert")
        }
        XCTAssertEqual(minPace, 290)
        XCTAssertEqual(maxPace, 310)
        XCTAssertLessThan(minPace, maxPace)
    }

    func testBuildVariantsRotateAndStayInBounds() {
        var names = Set<String>()
        for variant in 0..<3 {
            let workout = InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: variant)
            names.insert(workout.name)
            XCTAssertNotNil(workout.warmup, "every Build variant warms up")
            XCTAssertNotNil(workout.cooldown)
            for block in workout.blocks {
                XCTAssertGreaterThanOrEqual(block.iterations, 1)
                XCTAssertLessThanOrEqual(block.iterations, 10)
            }
        }
        XCTAssertEqual(names.count, 3, "three distinct Build variants")

        // variant index wraps around
        XCTAssertEqual(
            InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 3).name,
            InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 0).name
        )
    }

    func testBuildGuardRailsReduceRepsForLowVolume() {
        let normal = InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 0)
        let reduced = InstantWorkoutGenerator.workout(mode: .build, load: lowLoad, variant: 0)
        XCTAssertLessThanOrEqual(reduced.blocks[0].iterations, normal.blocks[0].iterations)
        XCTAssertGreaterThanOrEqual(reduced.blocks[0].iterations, 3)
    }

    func testExploreTargetsFractionOfLongestRun() {
        let workout = InstantWorkoutGenerator.workout(mode: .explore, load: typicalLoad)
        guard case .distanceMeters(let meters) = workout.blocks[0].steps[0].goal else {
            return XCTFail("Explore with history should have a distance target")
        }
        XCTAssertEqual(meters, 11_000, accuracy: 500) // 14 km × 0.8, rounded to 0.5 km
        XCTAssertEqual(meters.truncatingRemainder(dividingBy: 500), 0)
    }

    func testExploreFallsBackToOpenGoalForShortHistory() {
        let workout = InstantWorkoutGenerator.workout(mode: .explore, load: lowLoad)
        XCTAssertEqual(workout.blocks[0].steps[0].goal, .open)
    }

    func testRecoverIsShortSlowAndAlerted() {
        let workout = InstantWorkoutGenerator.workout(mode: .recover, load: typicalLoad)
        guard case .durationSeconds(let seconds) = workout.blocks[0].steps[0].goal else {
            return XCTFail("Recover must be time-based")
        }
        XCTAssertLessThanOrEqual(seconds, 30 * 60)

        guard case .paceRange(let minPace, _) = workout.blocks[0].steps[0].alert else {
            return XCTFail("Recover needs a pace ceiling")
        }
        XCTAssertGreaterThan(minPace, typicalLoad.typicalEasyPaceSecPerKm, "slower than easy pace")
    }

    // MARK: - Estimates & persistence

    func testEstimatesArePositiveAndSane() {
        for mode in WorkoutMode.allCases {
            let workout = InstantWorkoutGenerator.workout(mode: mode, load: typicalLoad)
            let duration = workout.estimatedDurationSeconds(referencePaceSecPerKm: 360)
            let distance = workout.estimatedDistanceMeters(referencePaceSecPerKm: 360)
            XCTAssertGreaterThanOrEqual(duration, 0, "\(mode)")
            XCTAssertLessThanOrEqual(duration, 3 * 3600, "\(mode)")
            XCTAssertLessThanOrEqual(distance, 42_195, "\(mode)")
        }
    }

    func testBlueprintJSONRoundTrip() throws {
        for mode in WorkoutMode.allCases {
            let original = InstantWorkoutGenerator.workout(mode: mode, load: typicalLoad, variant: 1)
            let decoded = try WorkoutBlueprint.decoded(from: original.encoded())
            XCTAssertEqual(decoded, original, "\(mode)")
        }
    }

    func testGenerationIsDeterministic() {
        XCTAssertEqual(
            InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 2),
            InstantWorkoutGenerator.workout(mode: .build, load: typicalLoad, variant: 2)
        )
    }
}
