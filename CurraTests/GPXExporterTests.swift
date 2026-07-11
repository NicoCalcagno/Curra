import XCTest
@testable import Curra

final class GPXExporterTests: XCTestCase {
    private let coordinates = [
        Coordinate(latitude: 45.4642, longitude: 9.19),
        Coordinate(latitude: 45.4650, longitude: 9.1910)
    ]

    func testGPXContainsTrackPointsAndName() {
        let gpx = GPXExporter.gpx(name: "Morning loop", coordinates: coordinates)

        XCTAssertTrue(gpx.hasPrefix("<?xml"))
        XCTAssertTrue(gpx.contains("<name>Morning loop</name>"))
        XCTAssertTrue(gpx.contains("lat=\"45.464200\""))
        XCTAssertTrue(gpx.contains("lon=\"9.191000\""))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt").count - 1, 2)
    }

    func testXMLSpecialCharactersAreEscaped() {
        let gpx = GPXExporter.gpx(name: "Park & <river> run", coordinates: coordinates)
        XCTAssertTrue(gpx.contains("<name>Park &amp; &lt;river&gt; run</name>"))
        XCTAssertFalse(gpx.contains("<river>"))
    }

    func testTemporaryFileIsWrittenWithGPXExtension() throws {
        let url = try GPXExporter.temporaryFile(name: "Test / route?", coordinates: coordinates)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "gpx")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("<trkpt"))
    }
}
