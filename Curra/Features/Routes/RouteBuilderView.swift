import MapKit
import SwiftData
import SwiftUI

/// Tap to drop waypoints; every change re-snaps the whole sequence to walkable
/// ways via OpenRouteService and shows live distance/ascent.
struct RouteBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var waypoints: [Coordinate] = []
    @State private var path: RoutedPath?
    @State private var isRouting = false
    @State private var errorMessage: String?
    @State private var routingTask: Task<Void, Never>?
    @State private var isNaming = false
    @State private var routeName = ""

    var body: some View {
        MapReader { proxy in
            Map {
                if let path {
                    MapPolyline(coordinates: path.coordinates.map(Self.clCoordinate))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                ForEach(Array(waypoints.enumerated()), id: \.offset) { index, waypoint in
                    Annotation("\(index + 1)", coordinate: Self.clCoordinate(waypoint)) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .onTapGesture { position in
                guard let coordinate = proxy.convert(position, from: .local) else { return }
                addWaypoint(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
        }
        .safeAreaInset(edge: .bottom) {
            controlBar
        }
        .navigationTitle("Route builder")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save route", isPresented: $isNaming) {
            TextField("Name", text: $routeName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            if !ORSClient.shared.isConfigured {
                Text("Add your OpenRouteService API key in Settings to snap routes to roads and trails.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if waypoints.isEmpty {
                Text("Tap the map to drop the starting point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(path.map { RunFormatters.distance($0.distanceMeters) } ?? "–")
                        .font(.headline).monospacedDigit()
                    if let ascent = path?.ascentMeters {
                        Text("↗ \(Int(ascent)) m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if isRouting { ProgressView() }
                Spacer()

                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(waypoints.isEmpty)

                Button(role: .destructive) {
                    clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(waypoints.isEmpty)

                Button("Save") {
                    routeName = ""
                    isNaming = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(path == nil)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    // MARK: - Actions

    private func addWaypoint(_ coordinate: Coordinate) {
        waypoints.append(coordinate)
        recompute()
    }

    private func undo() {
        _ = waypoints.popLast()
        recompute()
    }

    private func clear() {
        waypoints.removeAll()
        recompute()
    }

    private func recompute() {
        routingTask?.cancel()
        errorMessage = nil
        guard waypoints.count >= 2 else {
            path = nil
            return
        }

        let points = waypoints
        routingTask = Task {
            isRouting = true
            defer { isRouting = false }
            do {
                let routed = try await ORSClient.shared.directions(through: points)
                if !Task.isCancelled {
                    path = routed
                }
            } catch is CancellationError {
                // superseded by a newer edit
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func save() {
        guard let path else { return }
        let name = routeName.isEmpty
            ? "Route — \(RunFormatters.distance(path.distanceMeters))"
            : routeName
        let route = Route(
            name: name,
            encodedPolyline: path.encodedPolyline,
            distanceMeters: path.distanceMeters,
            elevationGainMeters: path.ascentMeters,
            source: .manual
        )
        modelContext.insert(route)
        try? modelContext.save()
        dismiss()
    }

    static func clCoordinate(_ coordinate: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
