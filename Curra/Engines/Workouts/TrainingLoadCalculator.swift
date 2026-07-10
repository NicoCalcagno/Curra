import Foundation

/// Summary of recent training used to parametrize generated workouts.
struct TrainingLoad: Equatable, Sendable {
    var weeklyKilometers: Double          // 14-day volume / 2
    var runCount7d: Int
    var daysSinceLastRun: Int?            // nil = no runs in history
    var typicalEasyPaceSecPerKm: Double
    var estimated5KPaceSecPerKm: Double
    var longestRecentRunKm: Double
    var lastRunWasQuality: Bool           // notably faster than easy, or long

    /// Conservative defaults for an empty history.
    static let fallback = TrainingLoad(
        weeklyKilometers: 15,
        runCount7d: 0,
        daysSinceLastRun: nil,
        typicalEasyPaceSecPerKm: 390,   // 6:30 /km
        estimated5KPaceSecPerKm: 330,   // 5:30 /km
        longestRecentRunKm: 5,
        lastRunWasQuality: false
    )
}

enum TrainingLoadCalculator {
    /// Computes load from the last 14 days of activity (pure).
    static func load(from activities: [ActivitySummary], now: Date = .now) -> TrainingLoad {
        let sorted = activities.sorted { $0.startDate > $1.startDate }
        guard let lastRun = sorted.first else { return .fallback }

        let recent = sorted.filter {
            now.timeIntervalSince($0.startDate) <= 14 * 86_400 && $0.startDate <= now
        }
        let last7d = recent.filter { now.timeIntervalSince($0.startDate) <= 7 * 86_400 }

        var load = TrainingLoad.fallback
        load.daysSinceLastRun = max(0, Int(now.timeIntervalSince(lastRun.startDate) / 86_400))
        load.runCount7d = last7d.count

        guard !recent.isEmpty else { return load }

        load.weeklyKilometers = recent.reduce(0) { $0 + $1.distanceMeters } / 1000 / 2
        load.longestRecentRunKm = (recent.map(\.distanceMeters).max() ?? 5_000) / 1000

        let paces = recent
            .filter { $0.distanceMeters >= 1_000 }
            .compactMap(\.paceSecondsPerKm)
            .sorted()
        if !paces.isEmpty {
            let median = paces[paces.count / 2]
            load.typicalEasyPaceSecPerKm = median * 1.08

            // 5K-effort proxy: best pace among runs >= 3 km, sharpened by 5%,
            // but always meaningfully faster than easy pace.
            let bestPace = recent
                .filter { $0.distanceMeters >= 3_000 }
                .compactMap(\.paceSecondsPerKm)
                .min() ?? median
            load.estimated5KPaceSecPerKm = min(bestPace * 0.95, load.typicalEasyPaceSecPerKm - 30)
        }

        if let lastPace = lastRun.paceSecondsPerKm {
            load.lastRunWasQuality = lastPace < load.typicalEasyPaceSecPerKm * 0.92
                || lastRun.durationSeconds > 70 * 60
        }
        return load
    }

    /// Which mode to suggest today.
    static func suggestedMode(for load: TrainingLoad) -> WorkoutMode {
        guard let daysSince = load.daysSinceLastRun else { return .maintain }
        if daysSince <= 1 && load.lastRunWasQuality { return .recover }
        if daysSince == 0 { return .recover }
        if daysSince >= 4 { return .maintain }
        if load.runCount7d >= 3 { return .build }
        return .maintain
    }
}
