import MapKit
import SwiftData
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var offline = OfflineMapService.shared
    @State private var offlineError: String?
    let route: Route

    var body: some View {
        let coordinates = Polyline.decode(route.encodedPolyline)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RouteMapContainer(route: route, coordinates: coordinates)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 24) {
                    stat("Distance", RunFormatters.distance(route.distanceMeters))
                    if let ascent = route.elevationGainMeters {
                        stat("Ascent", "\(Int(ascent)) m")
                    }
                    stat("Source", route.source == .manual ? "Built by hand" : "Suggested")
                }

                HStack {
                    Button {
                        route.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            route.isFavorite ? "Favorite" : "Add to favorites",
                            systemImage: route.isFavorite ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(.bordered)

                    if let gpxURL = try? GPXExporter.temporaryFile(
                        name: route.name,
                        coordinates: coordinates
                    ) {
                        ShareLink(item: gpxURL) {
                            Label("Export GPX", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                offlineSection
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Offline

    @ViewBuilder private var offlineSection: some View {
        let _ = offline.packsVersion // re-evaluate when packs change

        VStack(alignment: .leading, spacing: 8) {
            if let progress = offline.downloadProgress[route.id] {
                ProgressView(value: progress) {
                    Text("Downloading offline map…")
                        .font(.footnote)
                }
            } else if route.isOfflineAvailable && offline.isAvailableOffline(route.id) {
                HStack {
                    Label("Available offline", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Spacer()
                    Button("Remove download", role: .destructive) {
                        removeOffline()
                    }
                    .font(.footnote)
                }
            } else {
                Button {
                    downloadOffline()
                } label: {
                    Label("Download map for offline use", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }

            if let offlineError {
                Text(offlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func downloadOffline() {
        offlineError = nil
        Task {
            do {
                try await offline.download(route: route)
                route.isOfflineAvailable = true
                try? modelContext.save()
            } catch {
                offlineError = error.localizedDescription
            }
        }
    }

    private func removeOffline() {
        Task {
            await offline.removeDownload(routeID: route.id)
            route.isOfflineAvailable = false
            try? modelContext.save()
        }
    }
}

/// MapLibre-backed so downloaded routes render with no network (airplane mode).
struct RouteMapContainer: View {
    let route: Route
    let coordinates: [Coordinate]

    var body: some View {
        RouteLibreMapView(coordinates: coordinates)
    }
}
