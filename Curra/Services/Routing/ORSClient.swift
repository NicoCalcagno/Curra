import Foundation

enum RoutingError: Error, LocalizedError {
    case missingAPIKey
    case rateLimited
    case httpError(status: Int, body: String)
    case decoding(Error)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Enter your OpenRouteService API key in Settings."
        case .rateLimited: "Routing rate limit reached — wait a minute and retry."
        case .httpError(let status, _): "Routing service error (HTTP \(status))."
        case .decoding: "Unexpected routing response."
        case .noRoute: "No route found between these points."
        }
    }
}

struct RoutedPath: Equatable, Sendable {
    var coordinates: [Coordinate]
    var distanceMeters: Double
    var ascentMeters: Double?

    var encodedPolyline: String { Polyline.encode(coordinates) }
}

/// OpenRouteService directions client (foot-walking profile) — user-provided
/// free API key stored in the Keychain. Used for waypoint snapping in the
/// manual builder and `round_trip` generation for suggested loops.
@MainActor
final class ORSClient {
    static let shared = ORSClient()

    private static let apiKeyKeychainKey = "ors.apiKey"
    private let endpoint = URL(string: "https://api.openrouteservice.org/v2/directions/foot-walking")!
    private let keychain = KeychainStore.shared

    var apiKey: String {
        get { keychain.get(Self.apiKeyKeychainKey) ?? "" }
        set { keychain.set(newValue, for: Self.apiKeyKeychainKey) }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Public API

    /// Snaps a sequence of waypoints to walkable ways.
    func directions(through waypoints: [Coordinate]) async throws -> RoutedPath {
        try await request(body: [
            "coordinates": waypoints.map { [$0.longitude, $0.latitude] },
            "elevation": true,
            "instructions": false
        ])
    }

    /// Generates a loop of roughly `lengthMeters` starting and ending at `start`.
    /// Different seeds yield different loops.
    func roundTrip(from start: Coordinate, lengthMeters: Double, seed: Int) async throws -> RoutedPath {
        try await request(body: [
            "coordinates": [[start.longitude, start.latitude]],
            "elevation": true,
            "instructions": false,
            "options": [
                "round_trip": [
                    "length": lengthMeters,
                    "points": 4,
                    "seed": seed
                ]
            ]
        ])
    }

    // MARK: - Private

    private struct DirectionsResponse: Codable {
        struct Route: Codable {
            struct Summary: Codable {
                let distance: Double
                let ascent: Double?
            }

            let summary: Summary
            let geometry: String
        }

        let routes: [Route]
    }

    private func request(body: [String: Any]) async throws -> RoutedPath {
        guard isConfigured else { throw RoutingError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200:
            break
        case 429:
            throw RoutingError.rateLimited
        default:
            throw RoutingError.httpError(
                status: status,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded: DirectionsResponse
        do {
            decoded = try JSONDecoder().decode(DirectionsResponse.self, from: data)
        } catch {
            throw RoutingError.decoding(error)
        }
        guard let route = decoded.routes.first else { throw RoutingError.noRoute }

        // elevation=true → ORS returns 3D-encoded polylines.
        let coordinates = Polyline.decode(route.geometry, includesElevation: true)
        guard coordinates.count > 1 else { throw RoutingError.noRoute }

        return RoutedPath(
            coordinates: coordinates,
            distanceMeters: route.summary.distance,
            ascentMeters: route.summary.ascent
        )
    }
}
