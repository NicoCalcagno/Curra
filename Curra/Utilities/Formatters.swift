import Foundation

enum RunFormatters {
    /// "12.4 km"
    static func distance(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1000)
    }

    /// "1h 02m" or "48m"
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return "\(minutes)m"
    }

    /// "5:32 /km"
    static func pace(secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return "–" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    /// Goal progress value in the metric's display unit ("32.5", "4h 10m", "3").
    static func goalValue(_ value: Double, metric: GoalMetric) -> String {
        switch metric {
        case .distance:
            String(format: "%.1f", value / 1000)
        case .duration:
            duration(value)
        case .runCount:
            "\(Int(value))"
        case .elevationGain:
            "\(Int(value))"
        }
    }
}
