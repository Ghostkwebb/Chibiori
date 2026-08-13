import Foundation

public actor JikanAPIService {
    public static let shared = JikanAPIService()

    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.35 // 350ms throttle (~2.8 req/sec max)
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search
    public func fetchSearchResults(query: String, page: Int = 1) async throws -> [JikanAnimeDTO] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://api.jikan.moe/v4/anime?q=\(encodedQuery)&page=\(page)") else {
            throw APIError.invalidURL
        }

        do {
            return try await executeRequest(url: url)
        } catch {
            print("⚠️ Jikan search failed (\(error.localizedDescription)), falling back to AniList API...")
            return try await fetchAniListSearch(query: query, page: page)
        }
    }

    // MARK: - Seasonal Anime
    public func fetchCurrentSeason(page: Int = 1) async throws -> [JikanAnimeDTO] {
        guard let url = URL(string: "https://api.jikan.moe/v4/seasons/now?page=\(page)") else {
            throw APIError.invalidURL
        }

        do {
            return try await executeRequest(url: url)
        } catch {
            print("⚠️ Jikan seasonal query failed (\(error.localizedDescription)), falling back to AniList API...")
            return try await fetchAniListSeason(page: page)
        }
    }

    // MARK: - Top Anime
    public func fetchTopAnime(page: Int = 1, filter: String? = nil) async throws -> [JikanAnimeDTO] {
        var urlString = "https://api.jikan.moe/v4/top/anime?page=\(page)"
        if let filter = filter, !filter.isEmpty {
            urlString += "&filter=\(filter)"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        do {
            return try await executeRequest(url: url)
        } catch {
            print("⚠️ Jikan top anime query failed (\(error.localizedDescription)), falling back to AniList API...")
            return try await fetchAniListTop(filter: filter, page: page)
        }
    }

    // MARK: - Schedules / Weekly Calendar
    public func fetchSchedules(day: String? = nil, page: Int = 1) async throws -> [JikanAnimeDTO] {
        var urlString = "https://api.jikan.moe/v4/schedules?page=\(page)"
        if let day = day?.lowercased(), !day.isEmpty {
            urlString += "&filter=\(day)"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        do {
            return try await executeRequest(url: url)
        } catch {
            print("⚠️ Jikan schedule query failed (\(error.localizedDescription)), falling back to AniList/seasonal list...")
            let currentSeason = try await fetchCurrentSeason(page: page)
            if let targetDay = day?.lowercased(), !targetDay.isEmpty {
                let filtered = currentSeason.filter { anime in
                    if let broadcastDay = anime.broadcast?.day?.lowercased() {
                        return broadcastDay.contains(targetDay) || targetDay.contains(broadcastDay)
                    }
                    return false
                }
                return filtered.isEmpty ? currentSeason : filtered
            }
            return currentSeason
        }
    }

    // MARK: - Single Anime by ID
    public func fetchAnimeDetails(id: Int) async throws -> JikanAnimeDTO {
        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(id)/full") else {
            throw APIError.invalidURL
        }
        return try await executeSingleRequest(url: url)
    }

    // MARK: - Private Request Execution with Retries & Rate Throttling
    private func executeRequest(url: URL, maxRetries: Int = 2) async throws -> [JikanAnimeDTO] {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await throttle()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 7.0)
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
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                }

                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            } catch let decodingErr as DecodingError {
                throw APIError.decodingError(decodingErr)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        throw lastError
    }

    private func executeSingleRequest(url: URL, maxRetries: Int = 2) async throws -> JikanAnimeDTO {
        var lastError: Error = APIError.invalidResponse(statusCode: -1)

        for attempt in 1...maxRetries {
            try await throttle()

            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
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
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                }

                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            } catch let decodingErr as DecodingError {
                throw APIError.decodingError(decodingErr)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        throw lastError
    }

    // MARK: - AniList High-Availability Fallback
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
              genres
            }
          }
        }
        """
        return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25, "season": seasonStr, "seasonYear": year])
    }

    private func fetchAniListTop(filter: String?, page: Int) async throws -> [JikanAnimeDTO] {
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
              genres
            }
          }
        }
        """
        return try await executeAniListGraphQL(query: gql, variables: ["p": page, "per": 25, "sort": sortParam])
    }

    private func executeAniListGraphQL(query: String, variables: [String: Any]) async throws -> [JikanAnimeDTO] {
        guard let url = URL(string: "https://graphql.anilist.co") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let pageObj = dataObj["Page"] as? [String: Any],
              let mediaList = pageObj["media"] as? [[String: Any]] else {
            return []
        }

        var results: [JikanAnimeDTO] = []
        for item in mediaList {
            let id = item["idMal"] as? Int ?? item["id"] as? Int ?? 0
            guard id > 0 else { continue }

            let titleObj = item["title"] as? [String: Any]
            let romaji = titleObj?["romaji"] as? String
            let english = titleObj?["english"] as? String
            let native = titleObj?["native"] as? String
            let primaryTitle = english ?? romaji ?? native ?? "Untitled"

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

            let images = JikanImagesDTO(
                jpg: JikanImageFormatDTO(imageUrl: coverLarge, smallImageUrl: nil, largeImageUrl: coverLarge),
                webp: JikanImageFormatDTO(imageUrl: coverLarge, smallImageUrl: nil, largeImageUrl: coverLarge)
            )

            let dto = JikanAnimeDTO(
                malId: id,
                title: primaryTitle,
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
                duration: nil
            )
            results.append(dto)
        }

        return results.deduplicatedByID()
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
