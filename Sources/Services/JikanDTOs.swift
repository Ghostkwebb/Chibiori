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
            return "Server responded with status code \(code)."
        case .rateLimited:
            return "Rate limited by Jikan API. Please try again in a moment."
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

    enum CodingKeys: String, CodingKey {
        case malId = "mal_id"
        case title
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
    }

    public init(
        malId: Int,
        title: String,
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
        bannerImageURL: String? = nil
    ) {
        self.malId = malId
        self.title = title
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

    public var seasonYearFormatted: String? {
        if let season = season?.capitalized, let year = year {
            return "\(season) \(year)"
        } else if let year = year {
            return "\(year)"
        }
        return nil
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
