import Foundation

/// Fetches run activities from the Strava API, respecting rate limits.
/// Idempotency is guaranteed downstream by `DeduplicationEngine`, so an
/// interrupted import can simply be re-run.
@MainActor
final class StravaImportService {
    static let shared = StravaImportService()

    private let auth = StravaAuthService.shared
    private let limiter = StravaRateLimiter.shared
    private let baseURL = URL(string: "https://www.strava.com/api/v3")!
    private let pageSize = 200
    private let resumePageKey = "strava.import.lastCompletedPage"

    // MARK: - Public API

    /// One-shot historical import of all runs. Resumes from the last completed
    /// page if a previous attempt was interrupted (overlap is deduplicated).
    func fullImport(progress: ((Int) -> Void)? = nil) async throws -> [ActivitySummary] {
        var page = max(1, UserDefaults.standard.integer(forKey: self.resumePageKey))
        var summaries: [ActivitySummary] = []

        while true {
            let batch = try await fetchActivitiesPage(page: page, after: nil)
            if batch.isEmpty { break }
            summaries.append(contentsOf: batch.compactMap(StravaMapper.summary(from:)))
            progress?(summaries.count)
            UserDefaults.standard.set(page, forKey: resumePageKey)
            if batch.count < pageSize { break }
            page += 1
        }

        UserDefaults.standard.removeObject(forKey: resumePageKey)
        return summaries
    }

    /// Incremental sync: everything that started after `date`.
    func activities(after date: Date) async throws -> [ActivitySummary] {
        var page = 1
        var summaries: [ActivitySummary] = []
        while true {
            let batch = try await fetchActivitiesPage(page: page, after: date)
            if batch.isEmpty { break }
            summaries.append(contentsOf: batch.compactMap(StravaMapper.summary(from:)))
            if batch.count < pageSize { break }
            page += 1
        }
        return summaries
    }

    /// Lazily fetches the full-resolution GPS track for one activity
    /// (1 request each — used on demand, not during bulk import).
    func fetchDetailedPolyline(stravaID: Int64) async throws -> String? {
        let data = try await get(
            path: "activities/\(stravaID)/streams",
            query: [
                URLQueryItem(name: "keys", value: "latlng"),
                URLQueryItem(name: "key_by_type", value: "true")
            ]
        )
        let streams: StravaStreamsResponse
        do {
            streams = try JSONDecoder().decode(StravaStreamsResponse.self, from: data)
        } catch {
            throw StravaError.decoding(error)
        }
        guard let points = streams.latlng?.data, !points.isEmpty else { return nil }
        let coordinates = points.compactMap { pair -> Coordinate? in
            guard pair.count == 2 else { return nil }
            return Coordinate(latitude: pair[0], longitude: pair[1])
        }
        return Polyline.encode(coordinates)
    }

    // MARK: - Private

    private func fetchActivitiesPage(page: Int, after: Date?) async throws -> [StravaActivityDTO] {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(pageSize))
        ]
        if let after {
            query.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))))
        }
        let data = try await get(path: "athlete/activities", query: query)
        do {
            return try JSONDecoder().decode([StravaActivityDTO].self, from: data)
        } catch {
            throw StravaError.decoding(error)
        }
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var attempts = 0
        while true {
            attempts += 1
            try await limiter.permit()

            let token = try await auth.validAccessToken()
            var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            switch status {
            case 200:
                return data
            case 429 where attempts < 3:
                await limiter.reportRateLimited()
                continue
            case 429:
                throw StravaError.rateLimited
            default:
                throw StravaError.httpError(
                    status: status,
                    body: String(data: data, encoding: .utf8) ?? ""
                )
            }
        }
    }
}
