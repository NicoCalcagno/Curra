import Foundation

struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Google encoded polyline algorithm (precision 1e5), used both to decode
/// Strava `summary_polyline` strings and to encode HealthKit GPS routes.
/// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
enum Polyline {
    static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var previousLat = 0
        var previousLon = 0

        for coordinate in coordinates {
            let lat = Int((coordinate.latitude * 1e5).rounded())
            let lon = Int((coordinate.longitude * 1e5).rounded())
            output += encodeValue(lat - previousLat)
            output += encodeValue(lon - previousLon)
            previousLat = lat
            previousLon = lon
        }
        return output
    }

    static func decode(_ string: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        var index = string.startIndex
        var lat = 0
        var lon = 0

        while index < string.endIndex {
            guard let deltaLat = decodeValue(string, index: &index) else { break }
            guard let deltaLon = decodeValue(string, index: &index) else { break }
            lat += deltaLat
            lon += deltaLon
            coordinates.append(
                Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            )
        }
        return coordinates
    }

    // MARK: - Private

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : value << 1
        var output = ""
        while v >= 0x20 {
            output.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63))))
            v >>= 5
        }
        output.append(Character(UnicodeScalar(UInt8(v + 63))))
        return output
    }

    private static func decodeValue(_ string: String, index: inout String.Index) -> Int? {
        var result = 0
        var shift = 0
        var byte: Int

        repeat {
            guard index < string.endIndex,
                  let scalar = string[index].unicodeScalars.first,
                  scalar.value >= 63
            else { return nil }
            byte = Int(scalar.value) - 63
            result |= (byte & 0x1F) << shift
            shift += 5
            index = string.index(after: index)
        } while byte >= 0x20

        return (result & 1) != 0 ? ~(result >> 1) : result >> 1
    }
}
