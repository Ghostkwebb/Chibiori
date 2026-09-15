import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case rateLimited
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse(let code):
            if code == 429 {
                return "Anime database is temporarily rate-limiting requests. Please wait a moment and tap Retry."
            }
            return "Server responded with status code \(code)."
        case .rateLimited:
            return "Anime database is temporarily rate-limiting requests. Please wait a moment and tap Retry."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network connection error: \(error.localizedDescription)"
        }
    }
}

public struct JikanSearchResponse: Codable, Sendable {
    public let data: [JikanAnimeDTO]
    public let pagination: JikanPaginationDTO?
}

public struct JikanSingleResponse: Codable, Sendable {
    public let data: JikanAnimeDTO
}

public struct JikanPaginationDTO: Codable, Sendable {
    public let lastVisiblePage: Int?
    public let hasNextPage: Bool?

    enum CodingKeys: String, CodingKey {
        case lastVisiblePage = "last_visible_page"
        case hasNextPage = "has_next_page"
    }
}

public struct JikanAnimeDTO: Codable, Identifiable, Sendable {
    public var id: Int { malId }

    public let malId: Int
    public let title: String
    public let titleEnglish: String?
    public let titleJapanese: String?
    public let synopsis: String?
    public let images: JikanImagesDTO?
    public let status: String?
    public let episodes: Int?
    public let score: Double?
    public let scoredBy: Int?
    public let season: String?
    public let year: Int?
    public let broadcast: JikanBroadcastDTO?
    public let genres: [JikanNamedEntityDTO]?
    public let studios: [JikanNamedEntityDTO]?
    public let rating: String?
    public let duration: String?
    public let bannerImageURL: String?
    public let aired: JikanAiredDTO?
    public var dubbedLanguages: [String]?

    enum CodingKeys: String, CodingKey {
        case malId = "mal_id"
        case title
        case titleEnglish = "title_english"
        case titleJapanese = "title_japanese"
        case synopsis
        case images
        case status
        case episodes
        case score
        case scoredBy = "scored_by"
        case season
        case year
        case broadcast
        case genres
        case studios
        case rating
        case duration
        case bannerImageURL = "banner_image_url"
        case aired
        case dubbedLanguages
    }

    public init(
        malId: Int,
        title: String,
        titleEnglish: String? = nil,
        titleJapanese: String? = nil,
        synopsis: String? = nil,
        images: JikanImagesDTO? = nil,
        status: String? = nil,
        episodes: Int? = nil,
        score: Double? = nil,
        scoredBy: Int? = nil,
        season: String? = nil,
        year: Int? = nil,
        broadcast: JikanBroadcastDTO? = nil,
        genres: [JikanNamedEntityDTO]? = nil,
        studios: [JikanNamedEntityDTO]? = nil,
        rating: String? = nil,
        duration: String? = nil,
        bannerImageURL: String? = nil,
        aired: JikanAiredDTO? = nil,
        dubbedLanguages: [String]? = nil
    ) {
        self.malId = malId
        self.title = title
        self.titleEnglish = titleEnglish
        self.titleJapanese = titleJapanese
        self.synopsis = synopsis
        self.images = images
        self.status = status
        self.episodes = episodes
        self.score = score
        self.scoredBy = scoredBy
        self.season = season
        self.year = year
        self.broadcast = broadcast
        self.genres = genres
        self.studios = studios
        self.rating = rating
        self.duration = duration
        self.bannerImageURL = bannerImageURL
        self.aired = aired
        self.dubbedLanguages = dubbedLanguages
    }

    public var resolvedDubbedLanguages: [DubbedLanguage] {
        guard let list = dubbedLanguages, !list.isEmpty else {
            return [DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵")]
        }
        var resolvedList: [DubbedLanguage] = []
        var seenCodes = Set<String>()

        let hasExplicitNative = list.contains { DubbedLanguage.resolve(from: $0).code == "JP" }
        if !hasExplicitNative {
            let jp = DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵")
            resolvedList.append(jp)
            seenCodes.insert("JP")
        }

        for raw in list {
            let lang = DubbedLanguage.resolve(from: raw)
            if !seenCodes.contains(lang.code) {
                seenCodes.insert(lang.code)
                resolvedList.append(lang)
            }
        }

        return resolvedList.sorted {
            if $0.sortPriority != $1.sortPriority {
                return $0.sortPriority < $1.sortPriority
            }
            return $0.name < $1.name
        }
    }

    public var dubbedLanguagesDisplay: String {
        let list = resolvedDubbedLanguages
        if list.isEmpty { return "Unknown" }
        return list.map { lang in
            lang.isNativeAudio ? "\(lang.name) (Original)" : lang.name
        }.joined(separator: ", ")
    }

    public var coverImageURL: String {
        images?.webp?.largeImageUrl ??
        images?.jpg?.largeImageUrl ??
        images?.webp?.imageUrl ??
        images?.jpg?.imageUrl ??
        ""
    }

    public var genreNames: [String] {
        genres?.compactMap { $0.name } ?? []
    }

    public var studioNames: [String] {
        studios?.compactMap { $0.name } ?? []
    }

    public var startDateFormatted: String? {
        if let y = aired?.prop?.from?.year {
            return AnimeDateFormatter.format(year: y, month: aired?.prop?.from?.month, day: aired?.prop?.from?.day)
        }
        if let from = aired?.from {
            return AnimeDateFormatter.format(rawDateString: from)
        }
        return nil
    }

    public var airingEndDateFormatted: String? {
        if let y = aired?.prop?.to?.year {
            return AnimeDateFormatter.format(year: y, month: aired?.prop?.to?.month, day: aired?.prop?.to?.day)
        }
        if let to = aired?.to {
            return AnimeDateFormatter.format(rawDateString: to)
        }
        return nil
    }

    public var seasonYearFormatted: String? {
        if let season = season?.capitalized, let year = year {
            return "\(season) \(year)"
        } else if let year = year {
            return "\(year)"
        }
        return nil
    }

    public var airingDatesDisplay: String? {
        let start = startDateFormatted ?? seasonYearFormatted
        let end = airingEndDateFormatted
        let airing = AiringStatus.from(raw: status)

        switch airing {
        case .finishedAiring:
            if let start, let end {
                if start == end {
                    return start
                } else {
                    return "\(start) – \(end)"
                }
            } else if let end {
                return "Finished: \(end)"
            } else {
                return start
            }

        case .currentlyAiring:
            if let start {
                return "\(start) – Present"
            } else {
                return "Currently Airing"
            }

        case .notYetAired:
            if let start {
                return start
            } else {
                return "Upcoming"
            }

        case nil:
            if let start, let end, start != end {
                return "\(start) – \(end)"
            }
            return start ?? end
        }
    }

    public func displayTitle(for preference: TitleLanguagePreference = .english) -> String {
        switch preference {
        case .english:
            if let en = titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let jp = titleJapanese?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"
        case .romaji:
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if let jp = titleJapanese?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"
        case .native:
            if let jp = titleJapanese?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            return "Untitled Anime"
        }
    }

    public var titleVariants: [(preference: TitleLanguagePreference, title: String)] {
        var list: [(TitleLanguagePreference, String)] = []
        if let en = titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
            list.append((.english, en))
        }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append((.romaji, title))
        }
        if let jp = titleJapanese?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
            list.append((.native, jp))
        }
        return list
    }
}

public struct JikanImagesDTO: Codable, Sendable {
    public let jpg: JikanImageFormatDTO?
    public let webp: JikanImageFormatDTO?

    public init(jpg: JikanImageFormatDTO? = nil, webp: JikanImageFormatDTO? = nil) {
        self.jpg = jpg
        self.webp = webp
    }
}

public struct JikanImageFormatDTO: Codable, Sendable {
    public let imageUrl: String?
    public let smallImageUrl: String?
    public let largeImageUrl: String?

    public init(imageUrl: String? = nil, smallImageUrl: String? = nil, largeImageUrl: String? = nil) {
        self.imageUrl = imageUrl
        self.smallImageUrl = smallImageUrl
        self.largeImageUrl = largeImageUrl
    }

    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case smallImageUrl = "small_image_url"
        case largeImageUrl = "large_image_url"
    }
}

public struct JikanBroadcastDTO: Codable, Sendable {
    public let day: String?
    public let time: String?
    public let timezone: String?
    public let string: String?

    public init(day: String? = nil, time: String? = nil, timezone: String? = nil, string: String? = nil) {
        self.day = day
        self.time = time
        self.timezone = timezone
        self.string = string
    }
}

public struct JikanNamedEntityDTO: Codable, Identifiable, Sendable {
    public var id: Int { malId }
    public let malId: Int
    public let name: String

    public init(malId: Int, name: String) {
        self.malId = malId
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case malId = "mal_id"
        case name
    }
}

extension Array where Element == JikanAnimeDTO {
    public func deduplicatedByID() -> [JikanAnimeDTO] {
        var seen = Set<Int>()
        return filter { anime in
            if seen.contains(anime.malId) {
                return false
            }
            seen.insert(anime.malId)
            return true
        }
    }
}

public struct JikanAiredDTO: Codable, Sendable {
    public let from: String?
    public let to: String?
    public let prop: JikanAiredPropDTO?
    public let string: String?

    public init(from: String? = nil, to: String? = nil, prop: JikanAiredPropDTO? = nil, string: String? = nil) {
        self.from = from
        self.to = to
        self.prop = prop
        self.string = string
    }
}

public struct JikanAiredPropDTO: Codable, Sendable {
    public let from: JikanDatePropDTO?
    public let to: JikanDatePropDTO?

    public init(from: JikanDatePropDTO? = nil, to: JikanDatePropDTO? = nil) {
        self.from = from
        self.to = to
    }
}

public struct JikanDatePropDTO: Codable, Sendable {
    public let day: Int?
    public let month: Int?
    public let year: Int?

    public init(day: Int? = nil, month: Int? = nil, year: Int? = nil) {
        self.day = day
        self.month = month
        self.year = year
    }
}
