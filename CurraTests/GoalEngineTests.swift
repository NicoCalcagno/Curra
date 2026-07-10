import XCTest
@testable import Curra

final class GoalEngineTests: XCTestCase {
    /// Fixed calendar so week boundaries don't depend on the runner's locale:
    /// Gregorian, Monday first, Europe/Rome.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func run(on date: Date, km: Double = 10, seconds: Double = 3_000, elevation: Double? = nil) -> ActivitySummary {
        ActivitySummary(
            startDate: date,
            durationSeconds: seconds,
            distanceMeters: km * 1000,
            elevationGainMeters: elevation,
            averageHeartRate: nil,
            name: "Run",
            encodedPolyline: nil,
            source: .healthKit
        )
    }

    // MARK: - Period boundaries

    func testWeeklyPeriodStartsMonday() {
        // Wednesday 2026-07-08 → week is Mon 6 July ... Mon 13 July.
        let interval = GoalEngine.periodInterval(for: .weekly, containing: date(2026, 7, 8), calendar: calendar)
        XCTAssertEqual(interval.start, date(2026, 7, 6, 0, 0))
        XCTAssertEqual(interval.end, date(2026, 7, 13, 0, 0))
    }

    func testAggregationIncludesStartExcludesEnd() {
        let interval = DateInterval(start: date(2026, 7, 6, 0, 0), end: date(2026, 7, 13, 0, 0))
        let activities = [
            run(on: date(2026, 7, 6, 0, 0), km: 5),    // exactly at start → included
            run(on: date(2026, 7, 12, 23, 59), km: 7), // last minute → included
            run(on: date(2026, 7, 13, 0, 0), km: 9),   // exactly at end → excluded
            run(on: date(2026, 7, 5, 23, 59), km: 11)  // before start → excluded
        ]
        XCTAssertEqual(GoalEngine.aggregate(.distance, activities: activities, in: interval), 12_000)
    }

    // MARK: - Metrics

    func testEachMetricAggregates() {
        let interval = DateInterval(start: date(2026, 7, 6, 0, 0), end: date(2026, 7, 13, 0, 0))
        let activities = [
            run(on: date(2026, 7, 7), km: 10, seconds: 3_600, elevation: 120),
            run(on: date(2026, 7, 9), km: 5, seconds: 1_800, elevation: nil)
        ]
        XCTAssertEqual(GoalEngine.aggregate(.distance, activities: activities, in: interval), 15_000)
        XCTAssertEqual(GoalEngine.aggregate(.duration, activities: activities, in: interval), 5_400)
        XCTAssertEqual(GoalEngine.aggregate(.runCount, activities: activities, in: interval), 2)
        XCTAssertEqual(GoalEngine.aggregate(.elevationGain, activities: activities, in: interval), 120)
    }

    // MARK: - Progress

    func testProgressFractionClampsAtOne() {
        let now = date(2026, 7, 8)
        let progress = GoalEngine.progress(
            metric: .distance,
            period: .weekly,
            target: 10_000,
            activities: [run(on: date(2026, 7, 7), km: 15)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.paceStatus, .completed)
        XCTAssertEqual(progress.achieved, 15_000)
    }

    func testProgressBehindWhenLateInPeriodWithLittleVolume() {
        // Sunday evening, 10% of the target done → behind.
        let now = date(2026, 7, 12, 20, 0)
        let progress = GoalEngine.progress(
            metric: .distance,
            period: .weekly,
            target: 40_000,
            activities: [run(on: date(2026, 7, 7), km: 4)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(progress.paceStatus, .behind)
    }

    func testProgressAheadEarlyInPeriodWithVolume() {
        // Tuesday, 50% of the target done → ahead.
        let now = date(2026, 7, 7, 8, 0)
        let progress = GoalEngine.progress(
            metric: .distance,
            period: .weekly,
            target: 40_000,
            activities: [run(on: date(2026, 7, 6, 18, 0), km: 20)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(progress.paceStatus, .ahead)
    }

    func testZeroTargetDoesNotDivideByZero() {
        let progress = GoalEngine.progress(
            metric: .distance,
            period: .weekly,
            target: 0,
            activities: [],
            now: date(2026, 7, 8),
            calendar: calendar
        )
        XCTAssertEqual(progress.fraction, 0)
    }

    // MARK: - Closed periods (historicization)

    func testClosedPeriodsEnumeratesBackToCreation() {
        let creation = date(2026, 6, 17) // Wednesday, week of 15 June
        let now = date(2026, 7, 8)       // week of 6 July
        let periods = GoalEngine.closedPeriods(for: .weekly, from: creation, until: now, calendar: calendar)

        // Closed weeks: 29 Jun, 22 Jun, 15 Jun (creation week, partially covered).
        XCTAssertEqual(periods.count, 3)
        XCTAssertEqual(periods[0].start, date(2026, 6, 29, 0, 0))
        XCTAssertEqual(periods[1].start, date(2026, 6, 22, 0, 0))
        XCTAssertEqual(periods[2].start, date(2026, 6, 15, 0, 0))
    }

    func testClosedPeriodsExcludesCurrentPeriod() {
        let creation = date(2026, 7, 6)
        let now = date(2026, 7, 8) // same week as creation → nothing closed yet
        XCTAssertTrue(GoalEngine.closedPeriods(for: .weekly, from: creation, until: now, calendar: calendar).isEmpty)
    }

    func testClosedPeriodsRespectsLimit() {
        let creation = date(2020, 1, 1)
        let now = date(2026, 7, 8)
        let periods = GoalEngine.closedPeriods(for: .weekly, from: creation, until: now, calendar: calendar, limit: 26)
        XCTAssertEqual(periods.count, 26)
    }
}
