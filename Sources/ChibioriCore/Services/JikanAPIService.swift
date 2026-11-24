import Foundation

/// Thread-safe API facade coordinating AniList GraphQL (via `AniListClient`) and Jikan REST v4 fallbacks.
public actor JikanAPIService {
    public static let shared = JikanAPIService()

    private static let maxSearchCacheEntries = 50
    private static let maxDetailsCacheEntries = 200
    private static let maxScheduleCacheEntries = 20
    private static let categoryCacheTTL: TimeInterval = 600 // 10 minutes

    private var nextAllowedRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval

    private var searchCache: [String: [JikanAnimeDTO]] = [:]
    private var searchCacheOrder: [String] = []
    private var seasonCache: [Int: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var topAnimeCache: [String: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var scheduleCache: [String: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var scheduleCacheOrder: [String] = []
    private var detailsCache: [Int: JikanAnimeDTO] = [:]
    private var detailsCacheOrder: [Int] = []

    private let session: URLSession
    private let aniList: AniListClient

    public init(
        session: URLSession = .shared,
        aniList: AniListClient = .shared,
        minimumInterval: TimeInterval = 0.35
    ) {
        self.session = session
        self.aniList = aniList
        self.minimumInterval = minimumInterval
    }

    // MARK: - Search

    public func fetchSearchResults(query: String, page: Int = 1) async throws -> [JikanAnimeDTO] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        let cacheKey = "\(cleanQuery.lowercased())_p\(page)"
        if let cached = searchCache[cacheKey], !cached.isEmpty {
            return cached
        }

        do {
            let res = try await aniList.searchAnime(query: cleanQuery, page: page)
            if !res.isEmpty {
                storeSearchCache(res, for: cacheKey)
                return res
            }
        } catch {
            // Fall through to Jikan REST API fallback
        }

        let encodedQuery = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://api.jikan.moe/v4/anime?q=\(encodedQuery)&page=\(page)") else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            storeSearchCache(res, for: cacheKey)
        }
        return res
    }

    // MARK: - Seasonal Anime

    public func fetchCurrentSeason(page: Int = 1, now: Date = Date()) async throws -> [JikanAnimeDTO] {
        if let cached = seasonCache[page], Date().timeIntervalSince(cached.date) < Self.categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let season: String
        switch month {
        case 1...3: season = "WINTER"
        case 4...6: season = "SPRING"
        case 7...9: season = "SUMMER"
        default: season = "FALL"
        }

        do {
            let res = try await aniList.fetchSeasonalAnime(season: season, year: year, page: page)
            if !res.isEmpty {
                seasonCache[page] = (Date(), res)
                return res
            }
        } catch {
            // Fall through to Jikan REST API fallback
        }

        guard let url = URL(string: "https://api.jikan.moe/v4/seasons/now?page=\(page)") else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            seasonCache[page] = (Date(), res)
        }
        return res
    }

    // MARK: - Top Anime

    public func fetchTopAnime(page: Int = 1, filter: String? = nil) async throws -> [JikanAnimeDTO] {
        let cacheKey = "\(filter ?? "top")_p\(page)"
        if let cached = topAnimeCache[cacheKey], Date().timeIntervalSince(cached.date) < Self.categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        do {
            let res = try await aniList.fetchTopAnime(filter: filter, page: page)
            if !res.isEmpty {
                topAnimeCache[cacheKey] = (Date(), res)
                return res
            }
        } catch {
            // Fall through to Jikan REST API fallback
        }

        var urlString = "https://api.jikan.moe/v4/top/anime?page=\(page)"
        if let filter, !filter.isEmpty {
            urlString += "&filter=\(filter)"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            topAnimeCache[cacheKey] = (Date(), res)
        }
        return res
    }

    // MARK: - Schedules / Weekly Calendar

    public func fetchSchedules(day: String? = nil, page: Int = 1, referenceDate: Date = Date()) async throws -> [JikanAnimeDTO] {
        let normalizedDay = day?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(normalizedDay?.isEmpty == false ? normalizedDay! : "all")_p\(page)"
        if let cached = scheduleCache[cacheKey], Date().timeIntervalSince(cached.date) < Self.categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        let window = Self.airingWindowTimestamps(forDay: normalizedDay, referenceDate: referenceDate)
        do {
            let res = try await aniList.fetchAiringSchedule(
                startTimestamp: window.start,
                endTimestamp: window.end,
                page: page
            )
            if !res.isEmpty {
                storeScheduleCache(res, for: cacheKey)
                return res
            }
        } catch {
            // Fall through to Jikan REST schedules endpoint (never unfiltered season list)
        }

        var urlString = "https://api.jikan.moe/v4/schedules?page=\(page)"
        if let normalizedDay, !normalizedDay.isEmpty {
            urlString += "&filter=\(normalizedDay)"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            storeScheduleCache(res, for: cacheKey)
        }
        return res
    }

    // MARK: - Single Anime by ID

    public func fetchAnimeDetails(id: Int) async throws -> JikanAnimeDTO {
        if let cached = detailsCache[id] {
            return cached
        }

        if let details = try? await aniList.fetchDetails(malId: id) {
            storeDetailsCache(details, for: id)
            return details
        }

        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(id)/full") else {
            throw APIError.invalidURL
        }
        let res = try await executeSingleRequest(url: url)
        storeDetailsCache(res, for: id)
        return res
    }

    // MARK: - Day Window Calculation

    /// Computes `[startOfDay, endOfDay)` Unix timestamps in the local calendar for the requested weekday within the rolling 7-day window.
    public nonisolated static func airingWindowTimestamps(
        forDay day: String?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Int, end: Int) {
        let todayStart = calendar.startOfDay(for: referenceDate)

        guard let day = day?.lowercased(), let targetWeekday = weekdayNumber(from: day) else {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? todayStart.addingTimeInterval(7 * 86_400)
            return (Int(todayStart.timeIntervalSince1970), Int(weekEnd.timeIntervalSince1970))
        }

        for offset in 0..<7 {
            if let candidate = calendar.date(byAdding: .day, value: offset, to: todayStart),
               calendar.component(.weekday, from: candidate) == targetWeekday {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
                return (Int(candidate.timeIntervalSince1970), Int(nextDay.timeIntervalSince1970))
            }
        }

        let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        return (Int(todayStart.timeIntervalSince1970), Int(fallbackEnd.timeIntervalSince1970))
    }

    private nonisolated static func weekdayNumber(from day: String) -> Int? {
        switch day.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sunday", "sundays": return 1
        case "monday", "mondays": return 2
        case "tuesday", "tuesdays": return 3
        case "wednesday", "wednesdays": return 4
        case "thursday", "thursdays": return 5
        case "friday", "fridays": return 6
        case "saturday", "saturdays": return 7
        default: return nil
        }
    }

    // MARK: - Capped Cache Helpers

    private func storeSearchCache(_ value: [JikanAnimeDTO], for key: String) {
        if searchCache[key] == nil {
            searchCacheOrder.append(key)
        }
        searchCache[key] = value
        if searchCacheOrder.count > Self.maxSearchCacheEntries {
            let evicted = searchCacheOrder.removeFirst()
            searchCache.removeValue(forKey: evicted)
        }
    }

    private func storeScheduleCache(_ value: [JikanAnimeDTO], for key: String) {
        if scheduleCache[key] == nil {
            scheduleCacheOrder.append(key)
        }
        scheduleCache[key] = (Date(), value)
        if scheduleCacheOrder.count > Self.maxScheduleCacheEntries {
            let evicted = scheduleCacheOrder.removeFirst()
            scheduleCache.removeValue(forKey: evicted)
        }
    }

    private func storeDetailsCache(_ value: JikanAnimeDTO, for id: Int) {
        if detailsCache[id] == nil {
            detailsCacheOrder.append(id)
        }
        detailsCache[id] = value
        if detailsCacheOrder.count > Self.maxDetailsCacheEntries {
            let evicted = detailsCacheOrder.removeFirst()
            detailsCache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Jikan REST Request Execution with Slot-Reservation Throttling

    private func reserveThrottleSlot() async throws {
        let now = Date()
        let scheduled = max(now, nextAllowedRequestTime)
        nextAllowedRequestTime = scheduled.addingTimeInterval(minimumInterval)
        let delay = scheduled.timeIntervalSince(now)
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func executeRequest(url: URL, maxRetries: Int = 2) async throws -> [JikanAnimeDTO] {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await reserveThrottleSlot()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 4.5)
            request.setValue("Chibiori-macOS/1.0 (Local-First Tracker)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse(statusCode: -1)
                }

                if httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(JikanSearchResponse.self, from: data)
                    return decoded.data.deduplicatedByID()
                }

                if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    lastError = httpResponse.statusCode == 429 ? APIError.rateLimited : APIError.invalidResponse(statusCode: httpResponse.statusCode)
                    if attempt < maxRetries {
                        let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0.5
                        try await Task.sleep(nanoseconds: UInt64(min(max(retryAfter, 0.3), 3.0) * 1_000_000_000))
                        continue
                    }
                }

                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            } catch let decodingErr as DecodingError {
                throw APIError.decodingError(decodingErr)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }

        throw lastError
    }

    private func executeSingleRequest(url: URL, maxRetries: Int = 2) async throws -> JikanAnimeDTO {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await reserveThrottleSlot()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 4.5)
            request.setValue("Chibiori-macOS/1.0 (Local-First Tracker)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse(statusCode: -1)
                }

                if httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(JikanSingleResponse.self, from: data)
                    return decoded.data
                }

                if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    lastError = httpResponse.statusCode == 429 ? APIError.rateLimited : APIError.invalidResponse(statusCode: httpResponse.statusCode)
                    if attempt < maxRetries {
                        let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0.5
                        try await Task.sleep(nanoseconds: UInt64(min(max(retryAfter, 0.3), 3.0) * 1_000_000_000))
                        continue
                    }
                }

                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            } catch let decodingErr as DecodingError {
                throw APIError.decodingError(decodingErr)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }

        throw lastError
    }
}
