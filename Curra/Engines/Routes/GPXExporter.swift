import Foundation

/// Minimal GPX 1.1 track writer (pure) for exporting saved routes.
enum GPXExporter {
    static func gpx(name: String, coordinates: [Coordinate]) -> String {
        let points = coordinates
            .map { coordinate in
                String(
                    format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"/>",
                    coordinate.latitude,
                    coordinate.longitude
                )
            }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Curra" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(escaped(name))</name>
            <trkseg>
        \(points)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    /// Writes the GPX to a shareable temporary file.
    static func temporaryFile(name: String, coordinates: [Coordinate]) throws -> URL {
        let safeName = name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "route" : safeName)
            .appendingPathExtension("gpx")
        try gpx(name: name, coordinates: coordinates).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
