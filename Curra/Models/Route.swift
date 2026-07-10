import Foundation
import SwiftData

/// A saved route (built manually or auto-suggested). Populated from Phase 6 on;
/// defined now so the SwiftData schema stays frozen after Phase 1.
@Model
final class Route {
    var id: UUID
    var name: String
    var encodedPolyline: String
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var isFavorite: Bool
    var createdAt: Date
    var sourceRaw: String
    var isOfflineAvailable: Bool

    init(
        name: String,
        encodedPolyline: String,
        distanceMeters: Double,
        elevationGainMeters: Double? = nil,
        source: RouteSource,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.encodedPolyline = encodedPolyline
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.isFavorite = false
        self.createdAt = .now
        self.sourceRaw = source.rawValue
        self.isOfflineAvailable = false
    }

    var source: RouteSource {
        get { RouteSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
