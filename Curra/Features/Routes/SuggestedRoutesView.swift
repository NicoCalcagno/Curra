import MapKit
import SwiftData
import SwiftUI

/// "Give me an 8 km loop from here" → 2–3 alternatives via ORS round_trip.
struct SuggestedRoutesView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var start: Coordinate?
    @State private var targetKm: Double = 8
    @State private var suggestions: [RoutedPath] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var locationProvider = LocationProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                startPicker

                HStack {
                    Text("Distance")
                    Slider(value: $targetKm, in: 3...30, step: 1)
                    Text("\(Int(targetKm)) km")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }

                Button {
                    generate()
                } label: {
                    if isGenerating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Generate loops").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(start == nil || isGenerating || !ORSClient.shared.isConfigured)

                if !ORSClient.shared.isConfigured {
                    Text("Add your OpenRouteService API key in Settings first.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, path in
                    SuggestionCard(path: path, index: index) {
                        save(path, index: index)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Suggested routes")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Start point

    private var startPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starting point")
                .font(.headline)

            MapReader { proxy in
                Map {
                    if let start {
                        Marker("Start", coordinate: RouteBuilderView.clCoordinate(start))
                            .tint(.orange)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { position in
                    if let coordinate = proxy.convert(position, from: .local) {
                        start = Coordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    }
                }
            }

            Button {
                useCurrentLocation()
            } label: {
                Label("Use my location", systemImage: "location.fill")
            }
            .font(.footnote)
        }
    }

    // MARK: - Actions

    private func useCurrentLocation() {
        errorMessage = nil
        Task {
            do {
                start = try await locationProvider.currentLocation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func generate() {
        guard let start else { return }
        errorMessage = nil
        suggestions = []
        isGenerating = true

        Task {
            defer { isGenerating = false }
            var results: [RoutedPath] = []
            var failures = 0
            for seed in (0..<3).map({ _ in Int.random(in: 1...10_000) }) {
                do {
                    results.append(
                        try await ORSClient.shared.roundTrip(
                            from: start,
                            lengthMeters: targetKm * 1000,
                            seed: seed
                        )
                    )
                } catch {
                    failures += 1
                    if results.isEmpty && failures == 3 {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            suggestions = results
        }
    }

    private func save(_ path: RoutedPath, index: Int) {
        let route = Route(
            name: "Loop \(Int(targetKm)) km — option \(index + 1)",
            encodedPolyline: path.encodedPolyline,
            distanceMeters: path.distanceMeters,
            elevationGainMeters: path.ascentMeters,
            source: .suggested
        )
        modelContext.insert(route)
        try? modelContext.save()
    }
}

private struct SuggestionCard: View {
    let path: RoutedPath
    let index: Int
    let onSave: () -> Void

    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map {
                MapPolyline(coordinates: path.coordinates.map(RouteBuilderView.clCoordinate))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(false)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Option \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        Text(RunFormatters.distance(path.distanceMeters))
                        if let ascent = path.ascentMeters {
                            Text("↗ \(Int(ascent)) m")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isSaved ? "Saved" : "Save") {
                    onSave()
                    isSaved = true
                }
                .buttonStyle(.bordered)
                .disabled(isSaved)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}
