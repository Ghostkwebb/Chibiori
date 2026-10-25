import Foundation

public actor JikanAPIService {
    public static let shared = JikanAPIService()

    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.35 // 350ms throttle (~2.8 req/sec max)
    private var searchCache: [String: [JikanAnimeDTO]] = [:]
    private var seasonCache: [Int: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var topAnimeCache: [String: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var scheduleCache: [String: (date: Date, data: [JikanAnimeDTO])] = [:]
    private var detailsCache: [Int: JikanAnimeDTO] = [:]
    private let categoryCacheTTL: TimeInterval = 600 // 10 minutes cache
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search
    public func fetchSearchResults(query: String, page: Int = 1) async throws -> [JikanAnimeDTO] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return []
        }
        let cacheKey = "\(cleanQuery.lowercased())_p\(page)"
        if let cached = searchCache[cacheKey], !cached.isEmpty {
            return cached
        }

        // 1. High-speed edge query via AniList GraphQL (~350ms response)
        do {
            let res = try await fetchAniListSearch(query: cleanQuery, page: page)
            if !res.isEmpty {
                searchCache[cacheKey] = res
                return res
            }
        } catch {
            print("⚠️ AniList search error (\(error.localizedDescription)), falling back to Jikan API...")
        }

        // 2. Fallback to Jikan REST API if AniList is unreachable
        let encodedQuery = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://api.jikan.moe/v4/anime?q=\(encodedQuery)&page=\(page)") else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            searchCache[cacheKey] = res
        }
        return res
    }

    // MARK: - Seasonal Anime
    public func fetchCurrentSeason(page: Int = 1) async throws -> [JikanAnimeDTO] {
        if let cached = seasonCache[page], Date().timeIntervalSince(cached.date) < categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        // 1. Fast AniList seasonal query
        do {
            let res = try await fetchAniListSeason(page: page)
            if !res.isEmpty {
                seasonCache[page] = (Date(), res)
                return res
            }
        } catch {
            print("⚠️ AniList seasonal query error (\(error.localizedDescription)), falling back to Jikan API...")
        }

        // 2. Fallback to Jikan
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
        if let cached = topAnimeCache[cacheKey], Date().timeIntervalSince(cached.date) < categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        // 1. Fast AniList top anime query
        do {
            let res = try await fetchAniListTop(filter: filter, page: page)
            if !res.isEmpty {
                topAnimeCache[cacheKey] = (Date(), res)
                return res
            }
        } catch {
            print("⚠️ AniList top anime error (\(error.localizedDescription)), falling back to Jikan API...")
        }

        // 2. Fallback to Jikan
        var urlString = "https://api.jikan.moe/v4/top/anime?page=\(page)"
        if let filter = filter, !filter.isEmpty {
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
    public func fetchSchedules(day: String? = nil, page: Int = 1) async throws -> [JikanAnimeDTO] {
        let cacheKey = "\(day?.lowercased() ?? "all")_p\(page)"
        if let cached = scheduleCache[cacheKey], Date().timeIntervalSince(cached.date) < categoryCacheTTL, !cached.data.isEmpty {
            return cached.data
        }

        // Fast AniList seasonal list filtered by day
        do {
            let currentSeason = try await fetchCurrentSeason(page: page)
            if let targetDay = day?.lowercased(), !targetDay.isEmpty {
                let filtered = currentSeason.filter { anime in
                    if let broadcastDay = anime.broadcast?.day?.lowercased() {
                        return broadcastDay.contains(targetDay) || targetDay.contains(broadcastDay)
                    }
                    return false
                }
                let res = filtered.isEmpty ? currentSeason : filtered
                scheduleCache[cacheKey] = (Date(), res)
                return res
            }
            scheduleCache[cacheKey] = (Date(), currentSeason)
            return currentSeason
        } catch {
            print("⚠️ Schedule query from season list failed (\(error.localizedDescription)), falling back to Jikan...")
        }

        var urlString = "https://api.jikan.moe/v4/schedules?page=\(page)"
        if let day = day?.lowercased(), !day.isEmpty {
            urlString += "&filter=\(day)"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let res = try await executeRequest(url: url)
        if !res.isEmpty {
            scheduleCache[cacheKey] = (Date(), res)
        }
        return res
    }

    // MARK: - Single Anime by ID
    public func fetchAnimeDetails(id: Int) async throws -> JikanAnimeDTO {
        if let cached = detailsCache[id] {
            return cached
        }

        // Fast lookup via AniList
        if let details = try? await fetchAniListDetails(malId: id) {
            detailsCache[id] = details
            return details
        }

        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(id)/full") else {
            throw APIError.invalidURL
        }
        let res = try await executeSingleRequest(url: url)
        detailsCache[id] = res
        return res
    }

    // MARK: - Private Request Execution with Retries & Rate Throttling
    private func executeRequest(url: URL, maxRetries: Int = 1) async throws -> [JikanAnimeDTO] {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await throttle()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 3.5)
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
                        try await Task.sleep(nanoseconds: 300_000_000)
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

    private func executeSingleRequest(url: URL, maxRetries: Int = 1) async throws -> JikanAnimeDTO {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await throttle()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 4.0)
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
                        try await Task.sleep(nanoseconds: 300_000_000)
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

    // MARK: - AniList High-Speed Primary / Fallback Provider
    private func fetchAniListSearch(query: String, page: Int) async throws -> [JikanAnimeDTO] {
        let gql = """
        query ($p: Int, $per: Int, $s: String) {
          Page(page: $p, perPage: $per) {
            media(search: $s, type: ANIME, sort: POPULARITY_DESC) {
              id
              idMal
              title { romaji english native }
              description
              coverImage { large }
              status
              episodes
              averageScore
              seasonYear
              startDate { year month day }
              endDate { year month day }
              genres
            }
          }
        }
        """
        return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25, "s": query])
    }

    private func fetchAniListSeason(page: Int) async throws -> [JikanAnimeDTO] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: Date())
        let seasonStr: String
        switch month {
        case 1...3: seasonStr = "WINTER"
        case 4...6: seasonStr = "SPRING"
        case 7...9: seasonStr = "SUMMER"
        default: seasonStr = "FALL"
        }

        let gql = """
        query ($p: Int, $per: Int, $season: MediaSeason, $seasonYear: Int) {
          Page(page: $p, perPage: $per) {
            media(season: $season, seasonYear: $seasonYear, type: ANIME, sort: POPULARITY_DESC) {
              id
              idMal
              title { romaji english native }
              description
              coverImage { large }
              status
              episodes
              averageScore
              seasonYear
              startDate { year month day }
              endDate { year month day }
              genres
            }
          }
        }
        """
        return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25, "season": seasonStr, "seasonYear": year])
    }

    private func fetchAniListTop(filter: String?, page: Int) async throws -> [JikanAnimeDTO] {
        if filter == "airing" {
            let gql = """
            query ($p: Int, $per: Int) {
              Page(page: $p, perPage: $per) {
                media(type: ANIME, status: RELEASING, sort: [POPULARITY_DESC]) {
                  id
                  idMal
                  title { romaji english native }
                  description
                  coverImage { large }
                  status
                  episodes
                  averageScore
                  seasonYear
                  startDate { year month day }
                  endDate { year month day }
                  genres
                }
              }
            }
            """
            return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25])
        }

        let sortParam: [String] = (filter == "bypopularity") ? ["POPULARITY_DESC"] : ["SCORE_DESC"]
        let gql = """
        query ($p: Int, $per: Int, $sort: [MediaSort]) {
          Page(page: $p, perPage: $per) {
            media(type: ANIME, sort: $sort) {
              id
              idMal
              title { romaji english native }
              description
              coverImage { large }
              status
              episodes
              averageScore
              seasonYear
              startDate { year month day }
              endDate { year month day }
              genres
            }
          }
        }
        """
        return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25, "sort": sortParam])
    }

    private func fetchAniListDetails(malId: Int) async throws -> JikanAnimeDTO {
        let gql = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: ANIME) {
            id
            idMal
            title { romaji english native }
            description
            coverImage { large }
            status
            episodes
            averageScore
            seasonYear
            startDate { year month day }
            endDate { year month day }
            genres
          }
        }
        """
        guard let url = URL(string: "https://graphql.anilist.co") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 5.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["idMal": malId]]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let mediaObj = dataObj["Media"] as? [String: Any],
              let dto = parseAniListItem(mediaObj) else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        return dto
    }

    private func executeAniListGraphQL(query: String, variables: [String: Any], retryCount: Int = 1) async throws -> [JikanAnimeDTO] {
        guard let url = URL(string: "https://graphql.anilist.co") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 6.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        if http.statusCode == 429 {
            if retryCount > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return try await executeAniListGraphQL(query: query, variables: variables, retryCount: retryCount - 1)
            } else {
                throw APIError.rateLimited
            }
        }

        guard http.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let pageObj = dataObj["Page"] as? [String: Any],
              let mediaList = pageObj["media"] as? [[String: Any]] else {
            return []
        }

        var results: [JikanAnimeDTO] = []
        for item in mediaList {
            if let dto = parseAniListItem(item) {
                results.append(dto)
            }
        }

        return results.deduplicatedByID()
    }

    private func parseAniListItem(_ item: [String: Any]) -> JikanAnimeDTO? {
        let id = item["idMal"] as? Int ?? item["id"] as? Int ?? 0
        guard id > 0 else { return nil }

        let titleObj = item["title"] as? [String: Any]
        let romaji = (titleObj?["romaji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = (titleObj?["english"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let native = (titleObj?["native"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTitle = (romaji?.isEmpty == false ? romaji : nil) ?? (english?.isEmpty == false ? english : nil) ?? native ?? "Untitled"

        let desc = (item["description"] as? String)?
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<i>", with: "")
            .replacingOccurrences(of: "</i>", with: "")
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")

        let coverObj = item["coverImage"] as? [String: Any]
        let coverLarge = coverObj?["large"] as? String

        let statusRaw = item["status"] as? String ?? ""
        let episodes = item["episodes"] as? Int
        let avgScore = (item["averageScore"] as? Double ?? Double(item["averageScore"] as? Int ?? 0)) / 10.0
        let year = item["seasonYear"] as? Int
        let genreStrings = item["genres"] as? [String] ?? []
        let genreEntities = genreStrings.map { JikanNamedEntityDTO(malId: 0, name: $0) }

        let startObj = item["startDate"] as? [String: Any]
        let startDay = startObj?["day"] as? Int
        let startMonth = startObj?["month"] as? Int
        let startYear = startObj?["year"] as? Int

        let endObj = item["endDate"] as? [String: Any]
        let endDay = endObj?["day"] as? Int
        let endMonth = endObj?["month"] as? Int
        let endYear = endObj?["year"] as? Int

        var aired: JikanAiredDTO? = nil
        if startYear != nil || endYear != nil {
            let airedProp = JikanAiredPropDTO(
                from: JikanDatePropDTO(day: startDay, month: startMonth, year: startYear),
                to: JikanDatePropDTO(day: endDay, month: endMonth, year: endYear)
            )
            aired = JikanAiredDTO(prop: airedProp)
        }

        let images = JikanImagesDTO(
            jpg: JikanImageFormatDTO(imageUrl: coverLarge, smallImageUrl: nil, largeImageUrl: coverLarge),
            webp: JikanImageFormatDTO(imageUrl: coverLarge, smallImageUrl: nil, largeImageUrl: coverLarge)
        )

        return JikanAnimeDTO(
            malId: id,
            title: canonicalTitle,
            titleEnglish: english,
            titleJapanese: native,
            synopsis: desc,
            images: images,
            status: statusRaw,
            episodes: episodes,
            score: avgScore > 0 ? avgScore : nil,
            scoredBy: nil,
            season: nil,
            year: year,
            broadcast: nil,
            genres: genreEntities,
            studios: nil,
            rating: nil,
            duration: nil,
            aired: aired
        )
    }

    // MARK: - Rate Throttling
    private func throttle() async throws {
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRequestTime)
        if timeSinceLast < minimumInterval {
            let sleepNanoseconds = UInt64((minimumInterval - timeSinceLast) * 1_000_000_000)
            try await Task.sleep(nanoseconds: sleepNanoseconds)
        }
        lastRequestTime = Date()
    }
}
