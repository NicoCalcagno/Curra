import XCTest
@testable import Curra

final class TrainingLoadCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func run(daysAgo: Double, km: Double, paceSecPerKm: Double) -> ActivitySummary {
        ActivitySummary(
            startDate: now.addingTimeInterval(-daysAgo * 86_400),
            durationSeconds: km * paceSecPerKm,
            distanceMeters: km * 1000,
            elevationGainMeters: nil,
            averageHeartRate: nil,
            name: "Run",
            encodedPolyline: nil,
            source: .healthKit
        )
    }

    func testEmptyHistoryUsesFallback() {
        XCTAssertEqual(TrainingLoadCalculator.load(from: [], now: now), .fallback)
    }

    func testWeeklyVolumeIsFourteenDayAverageHalved() {
        let activities = [
            run(daysAgo: 1, km: 10, paceSecPerKm: 360),
            run(daysAgo: 5, km: 10, paceSecPerKm: 360),
            run(daysAgo: 10, km: 20, paceSecPerKm: 360),
            run(daysAgo: 20, km: 50, paceSecPerKm: 360) // outside 14d window → ignored
        ]
        let load = TrainingLoadCalculator.load(from: activities, now: now)
        XCTAssertEqual(load.weeklyKilometers, 20, accuracy: 0.01)
        XCTAssertEqual(load.runCount7d, 2)
        XCTAssertEqual(load.daysSinceLastRun, 1)
        XCTAssertEqual(load.longestRecentRunKm, 20, accuracy: 0.01)
    }

    func testEasyPaceDerivedFromMedianPlusMargin() {
        let activities = [
            run(daysAgo: 1, km: 10, paceSecPerKm: 340),
            run(daysAgo: 3, km: 10, paceSecPerKm: 360),
            run(daysAgo: 5, km: 10, paceSecPerKm: 380)
        ]
        let load = TrainingLoadCalculator.load(from: activities, now: now)
        XCTAssertEqual(load.typicalEasyPaceSecPerKm, 360 * 1.08, accuracy: 0.5)
    }

    func testEstimated5KPaceIsFasterThanEasyPace() {
        let activities = [
            run(daysAgo: 1, km: 10, paceSecPerKm: 350),
            run(daysAgo: 3, km: 5, paceSecPerKm: 330)
        ]
        let load = TrainingLoadCalculator.load(from: activities, now: now)
        XCTAssertLessThan(load.estimated5KPaceSecPerKm, load.typicalEasyPaceSecPerKm - 29)
    }

    func testOldLastRunStillReportsDaysSince() {
        let activities = [run(daysAgo: 30, km: 10, paceSecPerKm: 360)]
        let load = TrainingLoadCalculator.load(from: activities, now: now)
        XCTAssertEqual(load.daysSinceLastRun, 30)
        // No 14-day data → volume stays at fallback.
        XCTAssertEqual(load.weeklyKilometers, TrainingLoad.fallback.weeklyKilometers)
    }

    // MARK: - Mode suggestion

    func testSuggestsRecoverAfterQualityRunYesterday() {
        var load = TrainingLoad.fallback
        load.daysSinceLastRun = 1
        load.lastRunWasQuality = true
        XCTAssertEqual(TrainingLoadCalculator.suggestedMode(for: load), .recover)
    }

    func testSuggestsRecoverWhenAlreadyRanToday() {
        var load = TrainingLoad.fallback
        load.daysSinceLastRun = 0
        load.lastRunWasQuality = false
        XCTAssertEqual(TrainingLoadCalculator.suggestedMode(for: load), .recover)
    }

    func testSuggestsMaintainAfterLongBreak() {
        var load = TrainingLoad.fallback
        load.daysSinceLastRun = 6
        load.runCount7d = 0
        XCTAssertEqual(TrainingLoadCalculator.suggestedMode(for: load), .maintain)
    }

    func testSuggestsBuildWhenTrainingConsistently() {
        var load = TrainingLoad.fallback
        load.daysSinceLastRun = 2
        load.runCount7d = 3
        load.lastRunWasQuality = false
        XCTAssertEqual(TrainingLoadCalculator.suggestedMode(for: load), .build)
    }

    func testSuggestsMaintainForEmptyHistory() {
        XCTAssertEqual(TrainingLoadCalculator.suggestedMode(for: .fallback), .maintain)
    }
}
