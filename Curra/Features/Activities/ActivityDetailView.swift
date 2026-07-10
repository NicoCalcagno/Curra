import MapKit
import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    @Environment(ActivitySyncCoordinator.self) private var sync
    let activity: Activity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statsGrid

                if let encoded = activity.encodedPolyline {
                    ActivityMapView(encodedPolyline: encoded)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if !activity.hasDetailedRoute, activity.stravaID != nil {
                        Button("Load full-resolution route") {
                            Task { await sync.loadDetailedRoute(for: activity) }
                        }
                        .font(.footnote)
                    }
                }

                Label(sourceLabel, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                stat("Distance", RunFormatters.distance(activity.distanceMeters))
                stat("Time", RunFormatters.duration(activity.durationSeconds))
            }
            GridRow {
                stat("Pace", RunFormatters.pace(secondsPerKm: activity.paceSecondsPerKm))
                stat(
                    "Avg HR",
                    activity.averageHeartRate.map { "\(Int($0)) bpm" } ?? "–"
                )
            }
            if let elevation = activity.elevationGainMeters {
                GridRow {
                    stat("Elevation", "\(Int(elevation)) m")
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var sourceLabel: String {
        switch activity.source {
        case .strava: "Imported from Strava"
        case .healthKit: "From Apple Watch (HealthKit)"
        case .merged: "Apple Watch + Strava (merged)"
        }
    }
}

struct ActivityMapView: View {
    let encodedPolyline: String

    var body: some View {
        let coordinates = Polyline.decode(encodedPolyline)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        Map(initialPosition: .automatic) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.orange, lineWidth: 3)
            }
            if let start = coordinates.first {
                Marker("Start", coordinate: start)
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }
}
