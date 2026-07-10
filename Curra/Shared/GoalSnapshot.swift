import Foundation

/// Pre-formatted goal progress shared with the widget through the App Group.
/// The widget stays dumb: it renders labels computed by the app, so shared code
/// stays minimal and framework-free.
struct GoalSnapshot: Codable, Sendable {
    var title: String        // "Weekly distance"
    var valueLabel: String   // "32.5 of 40 km"
    var detailLabel: String  // "7.5 km to go"
    var fraction: Double     // 0...1
    var isCompleted: Bool
    var periodEnd: Date
    var updatedAt: Date

    static let appGroupID = "group.com.nicocalcagno.curra"
    static let storageKey = "goalSnapshot"

    static func load() -> GoalSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(GoalSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: storageKey)
    }
}
