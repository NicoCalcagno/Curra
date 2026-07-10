import Foundation

/// Client-side budget for Strava's read rate limits (100 req/15 min, 1 000/day),
/// enforced with a safety margin (90/15 min, 900/day). `permit()` suspends until
/// a slot is available instead of failing.
actor StravaRateLimiter {
    static let shared = StravaRateLimiter()

    private let windowLimit: Int
    private let dailyLimit: Int
    private var requestDates: [Date] = []

    init(windowLimit: Int = 90, dailyLimit: Int = 900) {
        self.windowLimit = windowLimit
        self.dailyLimit = dailyLimit
    }

    func permit() async throws {
        while true {
            let now = Date()
            prune(before: now.addingTimeInterval(-86_400))

            let inWindow = requestDates.filter { now.timeIntervalSince($0) < 900 }
            if inWindow.count < windowLimit && requestDates.count < dailyLimit {
                requestDates.append(now)
                return
            }

            let waitSeconds: TimeInterval
            if inWindow.count >= windowLimit, let oldest = inWindow.first {
                waitSeconds = max(1, 900 - now.timeIntervalSince(oldest) + 1)
            } else {
                // Daily budget exhausted: wait until the oldest request ages out.
                waitSeconds = max(60, 86_400 - now.timeIntervalSince(requestDates.first ?? now) + 1)
            }
            try await Task.sleep(for: .seconds(waitSeconds))
        }
    }

    /// Called on HTTP 429: block the window until the next 15-minute boundary.
    func reportRateLimited() {
        let now = Date()
        prune(before: now.addingTimeInterval(-86_400))
        let secondsIntoQuarter = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 900)
        let boundary = now.addingTimeInterval(900 - secondsIntoQuarter)
        // Backfill the window so permit() waits until the boundary.
        let filler = Array(
            repeating: boundary.addingTimeInterval(-899),
            count: max(0, windowLimit - requestDates.filter { now.timeIntervalSince($0) < 900 }.count)
        )
        requestDates.append(contentsOf: filler)
        requestDates.sort()
    }

    private func prune(before cutoff: Date) {
        requestDates.removeAll { $0 < cutoff }
    }
}
