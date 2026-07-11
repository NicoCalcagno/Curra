import SwiftData
import SwiftUI

struct RoutesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    var body: some View {
        Group {
            if routes.isEmpty {
                ContentUnavailableView(
                    "No saved routes",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Build a route by hand or generate loops of a chosen distance.")
                )
            } else {
                List {
                    ForEach(routes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRow(route: route)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(routes[index])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    SuggestedRoutesView()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                NavigationLink {
                    RouteBuilderView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name).font(.headline)
                HStack(spacing: 10) {
                    Text(RunFormatters.distance(route.distanceMeters))
                    if let ascent = route.elevationGainMeters {
                        Label("\(Int(ascent)) m", systemImage: "arrow.up.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if route.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            if route.isOfflineAvailable {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
