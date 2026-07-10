import Foundation

// MARK: - Wire models (Strava API v3)

struct StravaTokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct StravaActivityDTO: Codable, Sendable {
    struct Map: Codable, Sendable {
        let summaryPolyline: String?

        enum CodingKeys: String, CodingKey {
            case summaryPolyline = "summary_polyline"
        }
    }

    let id: Int64
    let name: String
    let distance: Double            // meters
    let movingTime: Double          // seconds
    let elapsedTime: Double         // seconds
    let totalElevationGain: Double? // meters
    let type: String?
    let sportType: String?
    let startDate: String           // ISO 8601, UTC ("2024-03-01T08:12:34Z")
    let averageHeartrate: Double?
    let map: Map?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type, map
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case sportType = "sport_type"
        case startDate = "start_date"
        case averageHeartrate = "average_heartrate"
    }
}

/// `key_by_type=true` response shape for `/activities/{id}/streams`.
struct StravaStreamsResponse: Codable, Sendable {
    struct LatLngStream: Codable, Sendable {
        let data: [[Double]] // [[lat, lon], ...]
    }

    let latlng: LatLngStream?
}

// MARK: - Mapping

enum StravaMapper {
    private static let runSportTypes: Set<String> = ["Run", "TrailRun", "VirtualRun"]

    static func isRun(_ dto: StravaActivityDTO) -> Bool {
        if let sportType = dto.sportType { return runSportTypes.contains(sportType) }
        return dto.type == "Run"
    }

    static func summary(from dto: StravaActivityDTO) -> ActivitySummary? {
        guard isRun(dto), let start = parseDate(dto.startDate) else { return nil }
        let polyline = dto.map?.summaryPolyline.flatMap { $0.isEmpty ? nil : $0 }
        return ActivitySummary(
            startDate: start,
            durationSeconds: dto.movingTime > 0 ? dto.movingTime : dto.elapsedTime,
            distanceMeters: dto.distance,
            elevationGainMeters: dto.totalElevationGain,
            averageHeartRate: dto.averageHeartrate,
            name: dto.name,
            encodedPolyline: polyline,
            source: .strava,
            stravaID: dto.id
        )
    }

    static func parseDate(_ iso: String) -> Date? {
        // ISO8601DateFormatter is not Sendable; create per call (cheap enough for imports).
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }
}

// MARK: - Errors

enum StravaError: Error, LocalizedError {
    case notConnected
    case missingCredentials
    case oauthFailed(String)
    case httpError(status: Int, body: String)
    case rateLimited
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Strava is not connected."
        case .missingCredentials: "Enter your Strava Client ID and Secret in Settings."
        case .oauthFailed(let reason): "Strava authorization failed: \(reason)"
        case .httpError(let status, _): "Strava API error (HTTP \(status))."
        case .rateLimited: "Strava rate limit reached — import will resume automatically."
        case .decoding: "Unexpected Strava API response."
        }
    }
}
