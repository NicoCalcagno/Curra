import CoreLocation
import Foundation
import MapLibre

enum OfflineMapError: Error, LocalizedError {
    case packCreationFailed(String)
    case downloadFailed(String)
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .packCreationFailed(let reason): "Could not start the download: \(reason)"
        case .downloadFailed(let reason): "Offline map download failed: \(reason)"
        case .quotaExceeded: "Offline map storage is full — remove some downloads in Settings."
        }
    }
}

/// Downloads and manages offline tile packs (one per route) through MapLibre's
/// offline storage, using the free OpenFreeMap vector style. A pack covers the
/// route's bounding box plus ~1 km, zoom 10–15.
///
/// MapLibre posts offline notifications on the main queue, so the service is
/// main-actor bound. Storage is capped at `maxTotalBytes`; beyond it new
/// downloads are refused until the user frees space in Settings.
@MainActor
final class OfflineMapService: NSObject, ObservableObject {
    static let shared = OfflineMapService()

    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let maxTotalBytes: UInt64 = 2 * 1024 * 1024 * 1024 // 2 GB

    @Published private(set) var downloadProgress: [UUID: Double] = [:]
    @Published private(set) var packsVersion = 0 // bumped so views re-read pack state

    private var completions: [UUID: CheckedContinuation<Void, Error>] = [:]

    override private init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(packProgressDidChange(_:)),
            name: .MLNOfflinePackProgressChanged,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(packDidFail(_:)),
            name: .MLNOfflinePackError,
            object: nil
        )
    }

    // MARK: - Queries

    private var packs: [MLNOfflinePack] {
        MLNOfflineStorage.shared.packs ?? []
    }

    func routeID(for pack: MLNOfflinePack) -> UUID? {
        UUID(uuidString: String(data: pack.context, encoding: .utf8) ?? "")
    }

    func pack(for routeID: UUID) -> MLNOfflinePack? {
        packs.first { self.routeID(for: $0) == routeID }
    }

    func isAvailableOffline(_ routeID: UUID) -> Bool {
        pack(for: routeID)?.state == .complete
    }

    /// (routeID, bytes) per stored pack — for the storage screen.
    func storedPacks() -> [(routeID: UUID, bytes: UInt64)] {
        packs.compactMap { pack in
            guard let id = routeID(for: pack) else { return nil }
            return (id, pack.progress.countOfBytesCompleted)
        }
    }

    var totalBytes: UInt64 {
        packs.reduce(0) { $0 + $1.progress.countOfBytesCompleted }
    }

    // MARK: - Download / remove

    func download(route: Route) async throws {
        guard totalBytes < Self.maxTotalBytes else { throw OfflineMapError.quotaExceeded }
        guard pack(for: route.id) == nil else { return }

        let coordinates = Polyline.decode(route.encodedPolyline)
        guard coordinates.count > 1 else { return }

        let region = MLNTilePyramidOfflineRegion(
            styleURL: Self.styleURL,
            bounds: Self.boundingBox(of: coordinates, bufferDegrees: 0.01),
            fromZoomLevel: 10,
            toZoomLevel: 15
        )
        let context = Data(route.id.uuidString.utf8)

        let pack: MLNOfflinePack = try await withCheckedThrowingContinuation { continuation in
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { pack, error in
                if let pack {
                    continuation.resume(returning: pack)
                } else {
                    continuation.resume(throwing: OfflineMapError.packCreationFailed(
                        error?.localizedDescription ?? "unknown error"
                    ))
                }
            }
        }

        downloadProgress[route.id] = 0
        defer {
            downloadProgress[route.id] = nil
            packsVersion += 1
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            completions[route.id] = continuation
            pack.resume()
        }
    }

    func removeDownload(routeID: UUID) async {
        guard let pack = pack(for: routeID) else { return }
        await withCheckedContinuation { continuation in
            MLNOfflineStorage.shared.removePack(pack) { _ in
                continuation.resume()
            }
        }
        packsVersion += 1
    }

    // MARK: - Notifications (main queue)

    @objc private func packProgressDidChange(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack,
              let routeID = routeID(for: pack)
        else { return }

        let progress = pack.progress
        if progress.countOfResourcesExpected > 0, completions[routeID] != nil {
            downloadProgress[routeID] = min(
                1,
                Double(progress.countOfResourcesCompleted) / Double(progress.countOfResourcesExpected)
            )
        }
        if pack.state == .complete {
            completions.removeValue(forKey: routeID)?.resume()
        }
    }

    @objc private func packDidFail(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack,
              let routeID = routeID(for: pack)
        else { return }
        let reason = (notification.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError)?
            .localizedDescription ?? "network error"
        completions.removeValue(forKey: routeID)?
            .resume(throwing: OfflineMapError.downloadFailed(reason))
    }

    // MARK: - Geometry

    static func boundingBox(of coordinates: [Coordinate], bufferDegrees: Double) -> MLNCoordinateBounds {
        var minLat = coordinates[0].latitude, maxLat = minLat
        var minLon = coordinates[0].longitude, maxLon = minLon
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat - bufferDegrees, longitude: minLon - bufferDegrees),
            ne: CLLocationCoordinate2D(latitude: maxLat + bufferDegrees, longitude: maxLon + bufferDegrees)
        )
    }
}
