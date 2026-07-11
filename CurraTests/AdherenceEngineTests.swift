import XCTest
@testable import Curra

final class AdherenceEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func planned(
        _ id: UUID = UUID(),
        daysFromBase: Double,
        estimatedKm: Double,
        status: PlannedWorkoutStatus = .scheduledOnWatch
    ) -> AdherenceEngine.PlannedSnapshot {
        AdherenceEngine.PlannedSnapshot(
            id: id,
            date: base.addingTimeInterval(daysFromBase * 86_400),
            estimatedDistanceMeters: estimatedKm * 1000,
            status: status
        )
    }

    private func run(
        _ id: UUID = UUID(),
        daysFromBase: Double,
        km: Double
    ) -> AdherenceEngine.CompletedRun {
        AdherenceEngine.CompletedRun(
            id: id,
            date: base.addingTimeInterval(daysFromBase * 86_400),
            distanceMeters: km * 1000
        )
    }

    func testMatchesRunOnSameDayWithinDistanceTolerance() {
        let plannedID = UUID(), activityID = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [planned(plannedID, daysFromBase: 0, estimatedKm: 10)],
            activities: [run(activityID, daysFromBase: 0.1, km: 11)], // +10%
            now: base.addingTimeInterval(86_400)
        )
        XCTAssertEqual(changes, [.completed(plannedID: plannedID, activityID: activityID)])
    }

    func testMatchesRunOneDayLate() {
        let plannedID = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [planned(plannedID, daysFromBase: 0, estimatedKm: 8)],
            activities: [run(daysFromBase: 1, km: 8)],
            now: base.addingTimeInterval(2 * 86_400)
        )
        guard case .completed(let id, _)? = changes.first else {
            return XCTFail("expected completion, got \(changes)")
        }
        XCTAssertEqual(id, plannedID)
    }

    func testRejectsRunWithWrongDistance() {
        let plannedID = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [planned(plannedID, daysFromBase: 0, estimatedKm: 10)],
            activities: [run(daysFromBase: 0, km: 4)], // -60%
            now: base.addingTimeInterval(3 * 86_400)
        )
        XCTAssertEqual(changes, [.skipped(plannedID: plannedID)])
    }

    func testOpenTargetMatchesAnyDistance() {
        let plannedID = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [planned(plannedID, daysFromBase: 0, estimatedKm: 0)],
            activities: [run(daysFromBase: 0, km: 3)],
            now: base
        )
        guard case .completed? = changes.first else {
            return XCTFail("open-goal session should match any run")
        }
    }

    func testNotSkippedWithinGracePeriod() {
        let changes = AdherenceEngine.evaluate(
            planned: [planned(daysFromBase: 0, estimatedKm: 10)],
            activities: [],
            now: base.addingTimeInterval(30 * 3600) // 30h < 36h grace
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testSkippedAfterGracePeriod() {
        let plannedID = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [planned(plannedID, daysFromBase: 0, estimatedKm: 10)],
            activities: [],
            now: base.addingTimeInterval(40 * 3600)
        )
        XCTAssertEqual(changes, [.skipped(plannedID: plannedID)])
    }

    func testOneActivitySatisfiesOnlyOnePlannedWorkout() {
        let first = UUID(), second = UUID()
        let changes = AdherenceEngine.evaluate(
            planned: [
                planned(first, daysFromBase: 0, estimatedKm: 10),
                planned(second, daysFromBase: 1, estimatedKm: 10)
            ],
            activities: [run(daysFromBase: 0.5, km: 10)],
            now: base.addingTimeInterval(12 * 3600)
        )
        XCTAssertEqual(changes.count, 1)
        guard case .completed? = changes.first else {
            return XCTFail("expected a single completion")
        }
    }

    func testCompletedAndSkippedWorkoutsAreLeftAlone() {
        let changes = AdherenceEngine.evaluate(
            planned: [
                planned(daysFromBase: 0, estimatedKm: 10, status: .completed),
                planned(daysFromBase: 0, estimatedKm: 10, status: .skipped)
            ],
            activities: [run(daysFromBase: 0, km: 10)],
            now: base.addingTimeInterval(10 * 86_400)
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testAdaptationTriggerNeedsTwoRecentSkips() {
        let now = base
        XCTAssertFalse(AdherenceEngine.shouldReduceNextWeek(
            skippedDates: [base.addingTimeInterval(-2 * 86_400)],
            now: now
        ))
        XCTAssertTrue(AdherenceEngine.shouldReduceNextWeek(
            skippedDates: [
                base.addingTimeInterval(-2 * 86_400),
                base.addingTimeInterval(-5 * 86_400)
            ],
            now: now
        ))
        XCTAssertFalse(AdherenceEngine.shouldReduceNextWeek(
            skippedDates: [
                base.addingTimeInterval(-10 * 86_400),
                base.addingTimeInterval(-12 * 86_400)
            ],
            now: now
        ), "old skips outside the trailing week don't count")
    }
}
