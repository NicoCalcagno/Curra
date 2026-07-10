import SwiftData
import SwiftUI

struct ActivityListView: View {
    @Environment(ActivitySyncCoordinator.self) private var sync
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]

    var body: some View {
        NavigationStack {
            Group {
                if activities.isEmpty {
                    ContentUnavailableView(
                        "No runs yet",
                        systemImage: "figure.run",
                        description: Text("Run with your Watch, or import your history from Strava in Settings.")
                    )
                } else {
                    List(activities) { activity in
                        NavigationLink(value: activity.id) {
                            ActivityRow(activity: activity)
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let activity = activities.first(where: { $0.id == id }) {
                            ActivityDetailView(activity: activity)
                        }
                    }
                }
            }
            .navigationTitle("Activities")
            .refreshable {
                await sync.runHealthKitSync()
                await sync.runStravaIncrementalSync()
            }
            .overlay(alignment: .bottom) {
                if let error = sync.lastError {
                    ErrorBanner(message: error)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activity.name)
                .font(.headline)
            HStack(spacing: 12) {
                Text(activity.startDate, format: .dateTime.day().month().year())
                Text(RunFormatters.distance(activity.distanceMeters))
                Text(RunFormatters.pace(secondsPerKm: activity.paceSecondsPerKm))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .padding(10)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .padding()
    }
}
