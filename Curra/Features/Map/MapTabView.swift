import SwiftUI

/// Map tab: personal heatmap now; the Routes section (builder, suggestions,
/// saved routes) joins it in Phase 6 as a second segment.
struct MapTabView: View {
    private enum Section: String, CaseIterable {
        case heatmap = "Heatmap"
        case routes = "Routes"
    }

    @State private var section: Section = .heatmap

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .heatmap:
                    HeatmapView()
                        .ignoresSafeArea(edges: .bottom)
                case .routes:
                    RoutesHomeView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Placeholder until Phase 6 lands the route builder.
struct RoutesHomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Routes coming soon",
            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
            description: Text("Build routes by hand or generate loops of a chosen distance.")
        )
    }
}
