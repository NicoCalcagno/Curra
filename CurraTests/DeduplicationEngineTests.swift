import XCTest
@testable import Curra

final class DeduplicationEngineTests: XCTestCase {
    private func summary(
        source: ActivitySource,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        distance: Double = 10_000,
        name: String = "Test Run",
        stravaID: Int64? = nil,
        healthKitUUID: String? = nil,
        heartRate: Double? = nil,
        polyline: String? = nil,
        hasDetailedRoute: Bool = false
    ) -> ActivitySummary {
        ActivitySummary(
            startDate: start,
            durationSeconds: 3_000,
            distanceMeters: distance,
            elevationGainMeters: nil,
            averageHeartRate: heartRate,
            name: name,
            encodedPolyline: polyline,
            source: source,
            stravaID: stravaID,
            healthKitUUID: healthKitUUID,
            hasDetailedRoute: hasDetailedRoute
        )
    }

    // MARK: - Hard keys

    func testReimportWithSameStravaIDIsSkipped() {
        let existing = [ExistingActivity(id: UUID(), summary: summary(source: .strava, stravaID: 42))]
        let decisions = DeduplicationEngine.decisions(
            incoming: [summary(source: .strava, stravaID: 42)],
            existing: existing
        )
        XCTAssertEqual(decisions, [.skip])
    }

    func testReimportWithSameHealthKitUUIDIsSkipped() {
        let uuid = UUID().uuidString
        let existing = [ExistingActivity(id: UUID(), summary: summary(source: .healthKit, healthKitUUID: uuid))]
        let decisions = DeduplicationEngine.decisions(
            incoming: [summary(source: .healthKit, healthKitUUID: uuid)],
            existing: existing
        )
        XCTAssertEqual(decisions, [.skip])
    }

    func testMergedActivityStillSkipsBothSourceKeys() {
        let uuid = UUID().uuidString
        var merged = summary(source: .merged, stravaID: 7, healthKitUUID: uuid)
        merged.source = .merged
        let existing = [ExistingActivity(id: UUID(), summary: merged)]

        XCTAssertEqual(
            DeduplicationEngine.decisions(incoming: [summary(source: .strava, stravaID: 7)], existing: existing),
            [.skip]
        )
        XCTAssertEqual(
            DeduplicationEngine.decisions(incoming: [summary(source: .healthKit, healthKitUUID: uuid)], existing: existing),
            [.skip]
        )
    }

    // MARK: - Fuzzy matching

    func testCrossSourceRunWithinWindowsIsMerged() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            ExistingActivity(
                id: id,
                summary: summary(source: .healthKit, start: start, distance: 10_000, healthKitUUID: "hk-1")
            )
        ]
        let incoming = summary(
            source: .strava,
            start: start.addingTimeInterval(120),
            distance: 10_150,
            stravaID: 99
        )

        let decisions = DeduplicationEngine.decisions(incoming: [incoming], existing: existing)
        guard case .merge(let existingID, let merged) = decisions.first else {
            return XCTFail("Expected merge, got \(decisions)")
        }
        XCTAssertEqual(existingID, id)
        XCTAssertEqual(merged.source, .merged)
        XCTAssertEqual(merged.stravaID, 99)
        XCTAssertEqual(merged.healthKitUUID, "hk-1")
    }

    func testRunOutsideTimeWindowIsInserted() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [ExistingActivity(id: UUID(), summary: summary(source: .healthKit, start: start))]
        let incoming = summary(source: .strava, start: start.addingTimeInterval(600), stravaID: 1)

        XCTAssertEqual(
            DeduplicationEngine.decisions(incoming: [incoming], existing: existing),
            [.insert(incoming)]
        )
    }

    func testRunOutsideDistanceToleranceIsInserted() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            ExistingActivity(id: UUID(), summary: summary(source: .healthKit, start: start, distance: 10_000))
        ]
        let incoming = summary(source: .strava, start: start, distance: 11_000, stravaID: 1)

        XCTAssertEqual(
            DeduplicationEngine.decisions(incoming: [incoming], existing: existing),
            [.insert(incoming)]
        )
    }

    func testDistanceToleranceScalesWithLongRuns() {
        // 4% of 30 km = 1 200 m > flat 200 m tolerance → still a match.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = summary(source: .healthKit, start: start, distance: 30_000)
        let b = summary(source: .strava, start: start, distance: 31_100)
        XCTAssertTrue(DeduplicationEngine.isFuzzyMatch(a, b))
    }

    func testSameSourceRunsAreNeverFuzzyMerged() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = summary(source: .strava, start: start, stravaID: 1)
        let b = summary(source: .strava, start: start.addingTimeInterval(60), stravaID: 2)
        XCTAssertFalse(DeduplicationEngine.isFuzzyMatch(a, b))
    }

    // MARK: - Merge field resolution

    func testMergePrefersHealthKitBodyAndStravaName() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let healthKit = summary(
            source: .healthKit,
            start: start,
            distance: 10_050,
            name: "Morning Run",
            healthKitUUID: "hk-1",
            heartRate: 152,
            polyline: "detailed",
            hasDetailedRoute: true
        )
        let strava = summary(
            source: .strava,
            start: start.addingTimeInterval(30),
            distance: 10_000,
            name: "Sunday long run!",
            stravaID: 5,
            polyline: "coarse"
        )

        let merged = DeduplicationEngine.merged(existing: healthKit, incoming: strava)
        XCTAssertEqual(merged.distanceMeters, 10_050) // HealthKit body wins
        XCTAssertEqual(merged.name, "Sunday long run!") // meaningful name wins
        XCTAssertEqual(merged.encodedPolyline, "detailed") // detailed route kept
        XCTAssertEqual(merged.averageHeartRate, 152)
        XCTAssertEqual(merged.source, .merged)

        // Same result regardless of which side arrived first.
        let mergedReversed = DeduplicationEngine.merged(existing: strava, incoming: healthKit)
        XCTAssertEqual(mergedReversed.distanceMeters, 10_050)
        XCTAssertEqual(mergedReversed.name, "Sunday long run!")
    }

    func testMergeFillsMissingPolylineFromStrava() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let healthKit = summary(source: .healthKit, start: start, healthKitUUID: "hk-1")
        let strava = summary(source: .strava, start: start, stravaID: 5, polyline: "coarse")

        let merged = DeduplicationEngine.merged(existing: healthKit, incoming: strava)
        XCTAssertEqual(merged.encodedPolyline, "coarse")
    }

    // MARK: - Batch behavior

    func testIntraBatchDuplicateIsMergedNotDoubleInserted() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let healthKit = summary(source: .healthKit, start: start, healthKitUUID: "hk-1")
        let strava = summary(source: .strava, start: start.addingTimeInterval(60), stravaID: 9)

        let decisions = DeduplicationEngine.decisions(incoming: [healthKit, strava], existing: [])
        XCTAssertEqual(decisions.count, 2)
        guard case .insert = decisions[0], case .merge = decisions[1] else {
            return XCTFail("Expected insert followed by merge, got \(decisions)")
        }
    }
}
