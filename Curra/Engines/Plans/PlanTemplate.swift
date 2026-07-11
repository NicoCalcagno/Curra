import Foundation

enum SessionKind: String, Codable, Equatable, Sendable {
    case easy
    case quality
    case long
}

/// Data-driven description of a multi-week plan. Volumes are relative — the
/// engine anchors the first week to the athlete's current load.
struct PlanTemplate: Equatable, Sendable {
    struct SessionSlot: Equatable, Sendable {
        /// Day offset from the week start (plans start on a Monday → 1 = Tuesday).
        var dayOffset: Int
        var kind: SessionKind
    }

    var raceType: RaceType
    var weekCount: Int
    var peakWeeklyKm: Double
    var minStartWeeklyKm: Double
    var sessions: [SessionSlot]

    static func template(for raceType: RaceType) -> PlanTemplate {
        switch raceType {
        case .fiveK:
            PlanTemplate(
                raceType: .fiveK,
                weekCount: 8,
                peakWeeklyKm: 32,
                minStartWeeklyKm: 12,
                sessions: [
                    SessionSlot(dayOffset: 1, kind: .easy),    // Tuesday
                    SessionSlot(dayOffset: 3, kind: .quality), // Thursday
                    SessionSlot(dayOffset: 5, kind: .long)     // Saturday
                ]
            )
        case .tenK:
            PlanTemplate(
                raceType: .tenK,
                weekCount: 10,
                peakWeeklyKm: 42,
                minStartWeeklyKm: 15,
                sessions: [
                    SessionSlot(dayOffset: 1, kind: .easy),
                    SessionSlot(dayOffset: 3, kind: .quality),
                    SessionSlot(dayOffset: 5, kind: .easy),
                    SessionSlot(dayOffset: 6, kind: .long)     // Sunday
                ]
            )
        case .half:
            PlanTemplate(
                raceType: .half,
                weekCount: 12,
                peakWeeklyKm: 55,
                minStartWeeklyKm: 20,
                sessions: [
                    SessionSlot(dayOffset: 1, kind: .easy),
                    SessionSlot(dayOffset: 3, kind: .quality),
                    SessionSlot(dayOffset: 5, kind: .easy),
                    SessionSlot(dayOffset: 6, kind: .long)
                ]
            )
        }
    }
}

extension RaceType {
    var displayName: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "Half marathon"
        }
    }
}
