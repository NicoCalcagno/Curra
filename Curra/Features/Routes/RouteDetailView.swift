import MapKit
import SwiftData
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.modelContext) private var modelContext
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
}

/// MapKit rendering for now; Phase 7 swaps this container for the MapLibre
/// offline-capable map without touching the rest of the screen.
struct RouteMapContainer: View {
    let route: Route
    let coordinates: [Coordinate]

    var body: some View {
        Map {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates.map(RouteBuilderView.clCoordinate))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            if let first = coordinates.first {
                Marker("Start", coordinate: RouteBuilderView.clCoordinate(first))
                    .tint(.green)
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }
}
