import MapKit
import SwiftData
import SwiftUI

/// All runs on one map. Rendering strategy per the plan: straight `MapPolyline`s
/// with translucent strokes; if pan/zoom degrades with a very large history,
/// swap the internals for a pre-rasterized tile overlay (measure first).
struct HeatmapView: View {
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]

    @State private var tracks: [UUID: [CLLocationCoordinate2D]] = [:]
    @State private var selectedYear: Int?
    @State private var minimumKm: Double = 0

    var body: some View {
        Map {
            ForEach(filteredActivities) { activity in
                if let coordinates = tracks[activity.id], coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(
                            .orange.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .topTrailing) {
            filterMenu
                .padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            summaryBadge
                .padding(10)
        }
        .task(id: activities.count) {
            await decodeTracks()
        }
    }

    // MARK: - Filtering

    private var filteredActivities: [Activity] {
        activities.filter { activity in
            guard activity.encodedPolyline != nil else { return false }
            if let selectedYear,
               Calendar.current.component(.year, from: activity.startDate) != selectedYear {
                return false
            }
            return activity.distanceMeters >= minimumKm * 1000
        }
    }

    private var availableYears: [Int] {
        Set(activities.map { Calendar.current.component(.year, from: $0.startDate) })
            .sorted(by: >)
    }

    private var filterMenu: some View {
        Menu {
            Menu("Year") {
                Button {
                    selectedYear = nil
                } label: {
                    label("All years", isSelected: selectedYear == nil)
                }
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        label(String(year), isSelected: selectedYear == year)
                    }
                }
            }
            Menu("Distance") {
                ForEach([0.0, 5, 10, 21], id: \.self) { km in
                    Button {
                        minimumKm = km
                    } label: {
                        label(km == 0 ? "Any distance" : "≥ \(Int(km)) km", isSelected: minimumKm == km)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .background(.background, in: Circle())
        }
    }

    private func label(_ text: String, isSelected: Bool) -> some View {
        HStack {
            Text(text)
            if isSelected { Image(systemName: "checkmark") }
        }
    }

    private var summaryBadge: some View {
        let shown = filteredActivities
        let km = shown.reduce(0) { $0 + $1.distanceMeters } / 1000
        return Text("\(shown.count) runs · \(Int(km)) km")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    // MARK: - Decoding (off-main, once per data change)

    private func decodeTracks() async {
        let encoded = activities.compactMap { activity -> (UUID, String)? in
            guard tracks[activity.id] == nil, let polyline = activity.encodedPolyline else {
                return nil
            }
            return (activity.id, polyline)
        }
        guard !encoded.isEmpty else { return }

        let decoded = await Task.detached(priority: .userInitiated) {
            var result: [UUID: [CLLocationCoordinate2D]] = [:]
            for (id, polyline) in encoded {
                result[id] = Polyline.decode(polyline).map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
            return result
        }.value

        tracks.merge(decoded) { _, new in new }
    }
}
