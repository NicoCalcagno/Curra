import XCTest
@testable import Curra

final class StravaMappingTests: XCTestCase {
    private func decodeActivities(_ json: String) throws -> [StravaActivityDTO] {
        try JSONDecoder().decode([StravaActivityDTO].self, from: Data(json.utf8))
    }

    func testMapsAthleteActivitiesElement() throws {
        let json = """
        [{
            "id": 123456789,
            "name": "Lakeside 10K",
            "distance": 10012.3,
            "moving_time": 2955,
            "elapsed_time": 3010,
            "total_elevation_gain": 84.0,
            "type": "Run",
            "sport_type": "Run",
            "start_date": "2024-03-01T08:12:34Z",
            "average_heartrate": 156.4,
            "map": { "summary_polyline": "_p~iF~ps|U_ulLnnqC" }
        }]
        """
        let dto = try XCTUnwrap(decodeActivities(json).first)
        let summary = try XCTUnwrap(StravaMapper.summary(from: dto))

        XCTAssertEqual(summary.stravaID, 123_456_789)
        XCTAssertEqual(summary.name, "Lakeside 10K")
        XCTAssertEqual(summary.distanceMeters, 10_012.3, accuracy: 0.01)
        XCTAssertEqual(summary.durationSeconds, 2_955) // moving_time preferred
        XCTAssertEqual(summary.elevationGainMeters, 84.0)
        XCTAssertEqual(summary.averageHeartRate ?? 0, 156.4, accuracy: 0.01)
        XCTAssertEqual(summary.encodedPolyline, "_p~iF~ps|U_ulLnnqC")
        XCTAssertEqual(summary.source, .strava)

        let expectedDate = try XCTUnwrap(StravaMapper.parseDate("2024-03-01T08:12:34Z"))
        XCTAssertEqual(summary.startDate, expectedDate)
    }

    func testNonRunActivitiesAreFilteredOut() throws {
        let json = """
        [{
            "id": 1, "name": "Ride", "distance": 30000,
            "moving_time": 3600, "elapsed_time": 3600,
            "type": "Ride", "sport_type": "Ride",
            "start_date": "2024-03-01T08:00:00Z"
        }]
        """
        let dto = try XCTUnwrap(decodeActivities(json).first)
        XCTAssertNil(StravaMapper.summary(from: dto))
    }

    func testTrailAndVirtualRunsAreIncluded() throws {
        for sportType in ["TrailRun", "VirtualRun"] {
            let json = """
            [{
                "id": 2, "name": "X", "distance": 8000,
                "moving_time": 2400, "elapsed_time": 2500,
                "type": "Run", "sport_type": "\(sportType)",
                "start_date": "2024-03-01T08:00:00Z"
            }]
            """
            let dto = try XCTUnwrap(decodeActivities(json).first)
            XCTAssertNotNil(StravaMapper.summary(from: dto), sportType)
        }
    }

    func testEmptyPolylineBecomesNil() throws {
        let json = """
        [{
            "id": 3, "name": "Treadmill", "distance": 5000,
            "moving_time": 1500, "elapsed_time": 1500,
            "type": "Run", "sport_type": "Run",
            "start_date": "2024-03-01T08:00:00Z",
            "map": { "summary_polyline": "" }
        }]
        """
        let dto = try XCTUnwrap(decodeActivities(json).first)
        XCTAssertNil(try XCTUnwrap(StravaMapper.summary(from: dto)).encodedPolyline)
    }

    func testFallsBackToElapsedTimeWhenMovingTimeIsZero() throws {
        let json = """
        [{
            "id": 4, "name": "Run", "distance": 5000,
            "moving_time": 0, "elapsed_time": 1500,
            "type": "Run", "sport_type": "Run",
            "start_date": "2024-03-01T08:00:00Z"
        }]
        """
        let dto = try XCTUnwrap(decodeActivities(json).first)
        XCTAssertEqual(try XCTUnwrap(StravaMapper.summary(from: dto)).durationSeconds, 1_500)
    }

    func testParsesFractionalSecondDates() {
        XCTAssertNotNil(StravaMapper.parseDate("2024-03-01T08:12:34.123Z"))
    }
}
