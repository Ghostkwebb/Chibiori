import Foundation

// MARK: - Codable AniList GraphQL DTOs

public struct AniListTitleDTO: Codable, Sendable {
    public let romaji: String?
    public let english: String?
    public let native: String?
}

public struct AniListCoverImageDTO: Codable, Sendable {
    public let large: String?
    public let extraLarge: String?
}

public struct AniListFuzzyDateDTO: Codable, Sendable {
    public let year: Int?
    public let month: Int?
    public let day: Int?
}

public struct AniListRelationNodeDTO: Codable, Sendable {
    public let id: Int?
    public let idMal: Int?
    public let type: String?
    public let format: String?
    public let status: String?
    public let episodes: Int?
    public let season: String?
    public let seasonYear: Int?
    public let startDate: AniListFuzzyDateDTO?
    public let description: String?
    public let coverImage: AniListCoverImageDTO?
    public let title: AniListTitleDTO?
    public let synonyms: [String]?
}

public struct AniListRelationEdgeDTO: Codable, Sendable {
    public let relationType: String?
    public let node: AniListRelationNodeDTO?
}

public struct AniListRelationsConnectionDTO: Codable, Sendable {
    public let edges: [AniListRelationEdgeDTO]?
}

public struct AniListVoiceActorDTO: Codable, Sendable {
    public let id: Int?
    public let languageV2: String?
}

public struct AniListCharacterEdgeDTO: Codable, Sendable {
    public let voiceActors: [AniListVoiceActorDTO]?
}

public struct AniListCharactersConnectionDTO: Codable, Sendable {
    public let edges: [AniListCharacterEdgeDTO]?
}

public struct AniListMediaNodeDTO: Codable, Sendable {
    public let id: Int?
    public let idMal: Int?
    public let type: String?
    public let format: String?
    public let status: String?
    public let episodes: Int?
    public let averageScore: Double?
    public let season: String?
    public let seasonYear: Int?
    public let startDate: AniListFuzzyDateDTO?
    public let endDate: AniListFuzzyDateDTO?
    public let description: String?
    public let coverImage: AniListCoverImageDTO?
    public let title: AniListTitleDTO?
    public let synonyms: [String]?
    public let genres: [String]?
    public let countryOfOrigin: String?
    public let relations: AniListRelationsConnectionDTO?
    public let characters: AniListCharactersConnectionDTO?

    /// Resolves the best English title from `title.english` or ASCII fallback synonyms.
    public var resolvedEnglishTitle: String? {
        if let english = title?.english?.trimmingCharacters(in: .whitespacesAndNewlines), !english.isEmpty {
            return english
        }
        for syn in synonyms ?? [] {
            let trimmed = syn.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.canBeConverted(to: .ascii), trimmed.count >= 2 {
                return trimmed
            }
        }
        return nil
    }

    /// Converts this AniList node into a `JikanAnimeDTO` using local `airingAt` broadcast metadata if available.
    public func asJikanDTO(airingAt: Int? = nil) -> JikanAnimeDTO? {
        let resolvedID = (idMal ?? 0) > 0 ? (idMal ?? 0) : (id ?? 0)
        guard resolvedID > 0 else { return nil }

        let romaji = title?.romaji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = title?.english?.trimmingCharacters(in: .whitespacesAndNewlines)
        let native = title?.native?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = (romaji?.isEmpty == false ? romaji : nil)
            ?? (english?.isEmpty == false ? english : nil)
            ?? native
            ?? "Untitled"

        let coverURL = coverImage?.large ?? coverImage?.extraLarge
        let cleanDescription = HTMLCleaner.strip(from: description)
        let normalizedScore = (averageScore ?? 0) > 0 ? (averageScore ?? 0) / 10.0 : nil
        let genreEntities = (genres ?? []).map { JikanNamedEntityDTO(malId: 0, name: $0) }

        var aired: JikanAiredDTO?
        if startDate?.year != nil || endDate?.year != nil {
            let airedProp = JikanAiredPropDTO(
                from: JikanDatePropDTO(day: startDate?.day, month: startDate?.month, year: startDate?.year),
                to: JikanDatePropDTO(day: endDate?.day, month: endDate?.month, year: endDate?.year)
            )
            aired = JikanAiredDTO(prop: airedProp)
        }

        var broadcast: JikanBroadcastDTO?
        if let airingAt {
            let airDate = Date(timeIntervalSince1970: TimeInterval(airingAt))
            let calendar = Calendar.current
            let weekdaySymbol = calendar.weekdaySymbols[max(0, min(6, calendar.component(.weekday, from: airDate) - 1))]
            let hour = calendar.component(.hour, from: airDate)
            let minute = calendar.component(.minute, from: airDate)
            let timeStr = String(format: "%02d:%02d", hour, minute)
            broadcast = JikanBroadcastDTO(
                day: "\(weekdaySymbol)s",
                time: timeStr,
                timezone: TimeZone.current.identifier,
                string: "\(weekdaySymbol)s at \(timeStr)"
            )
        }

        let images = JikanImagesDTO(
            jpg: JikanImageFormatDTO(imageUrl: coverURL, smallImageUrl: nil, largeImageUrl: coverURL),
            webp: JikanImageFormatDTO(imageUrl: coverURL, smallImageUrl: nil, largeImageUrl: coverURL)
        )

        return JikanAnimeDTO(
            malId: resolvedID,
            title: canonical,
            titleEnglish: english,
            titleJapanese: native,
            synopsis: cleanDescription,
            images: images,
            status: status,
            episodes: episodes,
            score: normalizedScore,
            scoredBy: nil,
            season: season?.lowercased(),
            year: seasonYear,
            broadcast: broadcast,
            genres: genreEntities,
            studios: nil,
            rating: nil,
            duration: nil,
            aired: aired
        )
    }

    /// Resolves effective ID (MAL ID when positive, otherwise negated AniList ID) and maps to a `RelatedAnimeItem`.
    public func toFranchiseRelatedItem() -> RelatedAnimeItem? {
        let mediaType = (type ?? "").uppercased()
        guard mediaType == "ANIME" else { return nil }
        let upperFormat = (format ?? "").uppercased()
        if upperFormat == "MANGA" || upperFormat == "NOVEL" || upperFormat == "ONE_SHOT" {
            return nil
        }

        let effectiveID: Int
        if let idMal, idMal > 0 {
            effectiveID = idMal
        } else if let id, id > 0 {
            effectiveID = -id
        } else {
            return nil
        }

        let romaji = title?.romaji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let english = title?.english?.trimmingCharacters(in: .whitespacesAndNewlines)
        let native = title?.native?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = !romaji.isEmpty ? romaji : (english ?? "Untitled")

        return RelatedAnimeItem(
            malID: effectiveID,
            relationType: "FRANCHISE",
            title: finalTitle,
            englishTitle: english,
            japaneseTitle: native,
            coverImageURL: coverImage?.large ?? coverImage?.extraLarge,
            format: format,
            status: status,
            episodes: episodes,
            season: season,
            seasonYear: seasonYear ?? startDate?.year,
            synopsis: HTMLCleaner.strip(from: description)
        )
    }
}

public struct AniListAiringScheduleNodeDTO: Codable, Sendable {
    public let airingAt: Int
    public let episode: Int?
    public let media: AniListMediaNodeDTO?
}

private struct AniListGraphQLRequest: Encodable {
    let query: String
    let variables: [String: AniListVariableValue]
}

private enum AniListVariableValue: Encodable {
    case int(Int)
    case intArray([Int])
    case string(String)
    case stringArray([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .intArray(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .stringArray(let value): try container.encode(value)
        }
    }
}

private struct AniListGraphQLResponse<DataPayload: Decodable>: Decodable {
    let data: DataPayload?
}

private struct AniListPagePayload<Node: Decodable>: Decodable {
    let Page: AniListPageContainer<Node>?
}

private struct AniListPageContainer<Node: Decodable>: Decodable {
    let media: [Node]?
    let airingSchedules: [Node]?
}

private struct AniListMediaPayload: Decodable {
    let Media: AniListMediaNodeDTO?
}

/// Shared AniList GraphQL client with typed `Codable` DTOs, slot-reservation rate limiting, and `Retry-After` 429 handling.
public actor AniListClient {
    public static let shared = AniListClient()

    private static let endpoint = URL(string: "https://graphql.anilist.co")!

    private let session: URLSession
    private let minimumInterval: TimeInterval
    private var nextAllowedRequestTime: Date = .distantPast

    public init(session: URLSession = .shared, minimumInterval: TimeInterval = 0.25) {
        self.session = session
        self.minimumInterval = minimumInterval
    }

    // MARK: - Discovery & Metadata Queries

    private static let mediaSelection = """
      id
      idMal
      title { romaji english native }
      description
      coverImage { large }
      status
      episodes
      averageScore
      season
      seasonYear
      startDate { year month day }
      endDate { year month day }
      genres
    """

    public func searchAnime(query: String, page: Int = 1, perPage: Int = 25) async throws -> [JikanAnimeDTO] {
        let gql = """
        query ($p: Int, $per: Int, $s: String) {
          Page(page: $p, perPage: $per) {
            media(search: $s, type: ANIME, sort: POPULARITY_DESC) {
              \(Self.mediaSelection)
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO> = try await execute(
            query: gql,
            variables: ["p": .int(page), "per": .int(perPage), "s": .string(query)],
            timeout: 8.0
        )
        return (payload.Page?.media ?? []).compactMap { $0.asJikanDTO() }.deduplicatedByID()
    }

    public func fetchSeasonalAnime(season: String, year: Int, page: Int = 1, perPage: Int = 25) async throws -> [JikanAnimeDTO] {
        let gql = """
        query ($p: Int, $per: Int, $season: MediaSeason, $seasonYear: Int) {
          Page(page: $p, perPage: $per) {
            media(season: $season, seasonYear: $seasonYear, type: ANIME, sort: POPULARITY_DESC) {
              \(Self.mediaSelection)
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO> = try await execute(
            query: gql,
            variables: [
                "p": .int(page),
                "per": .int(perPage),
                "season": .string(season),
                "seasonYear": .int(year)
            ],
            timeout: 8.0
        )
        return (payload.Page?.media ?? []).compactMap { $0.asJikanDTO() }.deduplicatedByID()
    }

    public func fetchTopAnime(filter: String?, page: Int = 1, perPage: Int = 25) async throws -> [JikanAnimeDTO] {
        if filter == "airing" {
            let gql = """
            query ($p: Int, $per: Int) {
              Page(page: $p, perPage: $per) {
                media(type: ANIME, status: RELEASING, sort: [POPULARITY_DESC]) {
                  \(Self.mediaSelection)
                }
              }
            }
            """
            let payload: AniListPagePayload<AniListMediaNodeDTO> = try await execute(
                query: gql,
                variables: ["p": .int(page), "per": .int(perPage)],
                timeout: 8.0
            )
            return (payload.Page?.media ?? []).compactMap { $0.asJikanDTO() }.deduplicatedByID()
        }

        let sortParam = (filter == "bypopularity") ? ["POPULARITY_DESC"] : ["SCORE_DESC"]
        let gql = """
        query ($p: Int, $per: Int, $sort: [MediaSort]) {
          Page(page: $p, perPage: $per) {
            media(type: ANIME, sort: $sort) {
              \(Self.mediaSelection)
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO> = try await execute(
            query: gql,
            variables: ["p": .int(page), "per": .int(perPage), "sort": .stringArray(sortParam)],
            timeout: 8.0
        )
        return (payload.Page?.media ?? []).compactMap { $0.asJikanDTO() }.deduplicatedByID()
    }

    public func fetchDetails(malId: Int) async throws -> JikanAnimeDTO {
        let gql = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: ANIME) {
            \(Self.mediaSelection)
          }
        }
        """
        let payload: AniListMediaPayload = try await execute(
            query: gql,
            variables: ["idMal": .int(malId)],
            timeout: 8.0
        )
        guard let dto = payload.Media?.asJikanDTO() else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        return dto
    }

    public func fetchAiringSchedule(
        startTimestamp: Int,
        endTimestamp: Int,
        page: Int = 1,
        perPage: Int = 50
    ) async throws -> [JikanAnimeDTO] {
        let gql = """
        query ($p: Int, $per: Int, $start: Int, $end: Int) {
          Page(page: $p, perPage: $per) {
            airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
              airingAt
              episode
              media {
                \(Self.mediaSelection)
              }
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListAiringScheduleNodeDTO> = try await execute(
            query: gql,
            variables: [
                "p": .int(page),
                "per": .int(perPage),
                "start": .int(startTimestamp),
                "end": .int(endTimestamp)
            ],
            timeout: 8.0
        )
        let schedules = payload.Page?.airingSchedules ?? []
        return schedules.compactMap { entry in
            entry.media?.asJikanDTO(airingAt: entry.airingAt)
        }.deduplicatedByID()
    }

    // MARK: - Batch Metadata, Relations & Franchise Queries

    public func fetchBatchMetadata(malIDs: [Int]) async -> [AniListMediaNodeDTO] {
        guard !malIDs.isEmpty else { return [] }
        let gql = """
        query ($ids: [Int]) {
          Page(page: 1, perPage: 50) {
            media(idMal_in: $ids, type: ANIME) {
              idMal
              coverImage { large extraLarge }
              description
              title { romaji english native }
              synonyms
              averageScore
              season
              seasonYear
              status
              episodes
              startDate { year month day }
              endDate { year month day }
              genres
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO>? = try? await execute(
            query: gql,
            variables: ["ids": .intArray(malIDs)],
            timeout: 12.0
        )
        return payload?.Page?.media ?? []
    }

    public func fetchRelations(malId: Int) async -> [AniListRelationEdgeDTO] {
        let isAniListId = malId < 0
        let targetId = isAniListId ? -malId : malId
        let mediaArg = isAniListId ? "id: $id" : "idMal: $id"
        let gql = """
        query ($id: Int) {
          Media(\(mediaArg), type: ANIME) {
            idMal
            relations {
              edges {
                relationType
                node {
                  id
                  idMal
                  type
                  format
                  status
                  episodes
                  season
                  seasonYear
                  description
                  coverImage { large }
                  title { romaji english native }
                }
              }
            }
          }
        }
        """
        let payload: AniListMediaPayload? = try? await execute(
            query: gql,
            variables: ["id": .int(targetId)],
            timeout: 10.0
        )
        return payload?.Media?.relations?.edges ?? []
    }

    public func fetchRelationsByTitle(_ title: String) async -> [AniListRelationEdgeDTO] {
        let gql = """
        query ($search: String) {
          Media(search: $search, type: ANIME) {
            idMal
            relations {
              edges {
                relationType
                node {
                  id
                  idMal
                  type
                  format
                  status
                  episodes
                  season
                  seasonYear
                  description
                  coverImage { large }
                  title { romaji english native }
                }
              }
            }
          }
        }
        """
        let payload: AniListMediaPayload? = try? await execute(
            query: gql,
            variables: ["search": .string(title)],
            timeout: 10.0
        )
        return payload?.Media?.relations?.edges ?? []
    }

    public func fetchFranchiseMedia(query: String) async -> [AniListMediaNodeDTO] {
        let gql = """
        query ($search: String) {
          Page(page: 1, perPage: 35) {
            media(search: $search, type: ANIME, sort: [START_DATE, POPULARITY_DESC]) {
              id
              idMal
              type
              format
              status
              episodes
              season
              seasonYear
              startDate { year month day }
              description
              coverImage { large }
              title { romaji english native }
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO>? = try? await execute(
            query: gql,
            variables: ["search": .string(query)],
            timeout: 10.0
        )
        return payload?.Page?.media ?? []
    }

    public func fetchBatchRelations(malIDs: [Int]) async -> [AniListMediaNodeDTO] {
        guard !malIDs.isEmpty else { return [] }
        let gql = """
        query ($ids: [Int]) {
          Page(page: 1, perPage: 50) {
            media(idMal_in: $ids, type: ANIME) {
              idMal
              title { romaji english native }
              synonyms
              relations {
                edges {
                  relationType
                  node {
                    id
                    idMal
                    title { romaji english native }
                    synonyms
                    status
                    season
                    seasonYear
                    description
                    coverImage { large }
                  }
                }
              }
            }
          }
        }
        """
        let payload: AniListPagePayload<AniListMediaNodeDTO>? = try? await execute(
            query: gql,
            variables: ["ids": .intArray(malIDs)],
            timeout: 10.0
        )
        return payload?.Page?.media ?? []
    }

    public func fetchVoiceLanguages(malId: Int) async -> (country: String?, languages: [String])? {
        let gql = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: ANIME) {
            countryOfOrigin
            characters(sort: [ROLE, RELEVANCE, ID], page: 1, perPage: 25) {
              edges {
                voiceActors {
                  id
                  languageV2
                }
              }
            }
          }
        }
        """
        guard let payload: AniListMediaPayload = try? await execute(
            query: gql,
            variables: ["idMal": .int(malId)],
            timeout: 8.0,
            maxRetries: 0
        ), let media = payload.Media else {
            return nil
        }

        let langs = Set(
            (media.characters?.edges ?? [])
                .flatMap { $0.voiceActors ?? [] }
                .compactMap(\.languageV2)
                .filter { !$0.isEmpty }
        )
        return (media.countryOfOrigin, Array(langs))
    }

    // MARK: - Transport & Slot-Reservation Throttling

    private func reserveThrottleSlot() async {
        let now = Date()
        let scheduledTime = max(now, nextAllowedRequestTime)
        nextAllowedRequestTime = scheduledTime.addingTimeInterval(minimumInterval)
        let delay = scheduledTime.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func execute<Payload: Decodable>(
        query: String,
        variables: [String: AniListVariableValue],
        timeout: TimeInterval,
        maxRetries: Int = 1
    ) async throws -> Payload {
        var attempt = 0
        let body = AniListGraphQLRequest(query: query, variables: variables)
        let httpBody = try JSONEncoder().encode(body)

        while true {
            await reserveThrottleSlot()

            var request = URLRequest(url: Self.endpoint, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")
            request.httpBody = httpBody

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }

            if http.statusCode == 429 {
                if attempt < maxRetries {
                    attempt += 1
                    let retryAfterSeconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1.0
                    let cappedDelay = max(0.5, min(retryAfterSeconds, 5.0))
                    try? await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
                    continue
                }
                throw APIError.rateLimited
            }

            guard http.statusCode == 200 else {
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }

            let decoded = try JSONDecoder().decode(AniListGraphQLResponse<Payload>.self, from: data)
            guard let payload = decoded.data else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            return payload
        }
    }
}
