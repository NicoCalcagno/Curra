import SwiftUI
import WidgetKit

struct GoalEntry: TimelineEntry {
    let date: Date
    let snapshot: GoalSnapshot?
}

struct GoalTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalEntry {
        GoalEntry(
            date: .now,
            snapshot: GoalSnapshot(
                title: "Weekly distance",
                valueLabel: "32.5 of 40 km",
                detailLabel: "7.5 km to go",
                fraction: 0.81,
                isCompleted: false,
                periodEnd: .now,
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalEntry) -> Void) {
        completion(GoalEntry(date: .now, snapshot: GoalSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalEntry>) -> Void) {
        let entry = GoalEntry(date: .now, snapshot: GoalSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurraGoalWidget", provider: GoalTimelineProvider()) { entry in
            GoalWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Goal progress")
        .description("Your active running goal at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoalEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "target")
                Text("Set a goal in Curra")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func small(_ snapshot: GoalSnapshot) -> some View {
        VStack(spacing: 8) {
            ring(snapshot)
                .frame(width: 64, height: 64)
            Text(snapshot.valueLabel)
                .font(.caption.weight(.medium))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private func medium(_ snapshot: GoalSnapshot) -> some View {
        HStack(spacing: 16) {
            ring(snapshot)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.headline)
                Text(snapshot.valueLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(snapshot.detailLabel)
                    .font(.caption)
                    .foregroundStyle(snapshot.isCompleted ? .green : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func ring(_ snapshot: GoalSnapshot) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, snapshot.fraction))
                .stroke(
                    snapshot.isCompleted ? Color.green : Color.orange,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int((snapshot.fraction * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}
