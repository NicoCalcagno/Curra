import XCTest
@testable import Curra

final class PolylineTests: XCTestCase {
    /// Reference vector from Google's polyline algorithm documentation.
    func testEncodesGoogleReferenceVector() {
        let coordinates = [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453)
        ]
        XCTAssertEqual(Polyline.encode(coordinates), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    func testDecodesGoogleReferenceVector() {
        let decoded = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].latitude, 38.5, accuracy: 1e-5)
        XCTAssertEqual(decoded[0].longitude, -120.2, accuracy: 1e-5)
        XCTAssertEqual(decoded[2].latitude, 43.252, accuracy: 1e-5)
        XCTAssertEqual(decoded[2].longitude, -126.453, accuracy: 1e-5)
    }

    func testRoundTripPreservesCoordinatesWithinPrecision() {
        let coordinates = (0..<500).map { index in
            Coordinate(
                latitude: 45.4642 + Double(index) * 0.0001,
                longitude: 9.19 + Double(index) * 0.00013
            )
        }
        let decoded = Polyline.decode(Polyline.encode(coordinates))

        XCTAssertEqual(decoded.count, coordinates.count)
        for (original, roundTripped) in zip(coordinates, decoded) {
            XCTAssertEqual(original.latitude, roundTripped.latitude, accuracy: 1e-5)
            XCTAssertEqual(original.longitude, roundTripped.longitude, accuracy: 1e-5)
        }
    }

    func testNegativeAndZeroCoordinates() {
        let coordinates = [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: -33.8688, longitude: 151.2093)
        ]
        let decoded = Polyline.decode(Polyline.encode(coordinates))
        XCTAssertEqual(decoded[0].latitude, 0, accuracy: 1e-5)
        XCTAssertEqual(decoded[1].latitude, -33.8688, accuracy: 1e-5)
        XCTAssertEqual(decoded[1].longitude, 151.2093, accuracy: 1e-5)
    }

    func testDecodeEmptyStringReturnsEmpty() {
        XCTAssertTrue(Polyline.decode("").isEmpty)
    }

    /// Hand-computed 3D polyline: lat delta 1, lon delta 1 encode to "AA";
    /// elevation delta 100 encodes to "gE" and must be skipped.
    func testDecodeWithElevationSkipsThirdDimension() {
        let decoded = Polyline.decode("AAgE", includesElevation: true)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].latitude, 0.00001, accuracy: 1e-9)
        XCTAssertEqual(decoded[0].longitude, 0.00001, accuracy: 1e-9)
    }

    func testDecodeWithElevationHandlesMultiplePoints() {
        // Two triplets: (1e-5, 1e-5, +1.00 m) then deltas (1, 1, 0) → "AAgEAA?"
        // where '?' encodes 0.
        let decoded = Polyline.decode("AAgEAA?", includesElevation: true)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[1].latitude, 0.00002, accuracy: 1e-9)
        XCTAssertEqual(decoded[1].longitude, 0.00002, accuracy: 1e-9)
    }
}
