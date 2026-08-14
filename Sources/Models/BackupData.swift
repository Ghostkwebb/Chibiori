import Foundation

public struct AnimeBackupRoot: Codable, Sendable {
    public let version: String
    public let exportedAt: String
    public let app: String
    public let records: [AnimeBackupRecord]

    public init(version: String = "1.0", exportedAt: String, app: String = "Chibiori", records: [AnimeBackupRecord]) {
        self.version = version
        self.exportedAt = exportedAt
        self.app = app
        self.records = records
    }
}

public struct AnimeBackupRecord: Codable, Identifiable, Sendable {
    public var id: Int { malID }

    public let malID: Int
    public let title: String
    public let watchStatus: String
    public let currentEpisodeProgress: Int
    public let userRating: Int?
    public let personalNotes: String
    public let dateAdded: String
    public let dateStarted: String?
    public let dateCompleted: String?
    public let airingStatus: String
    public let totalEpisodes: Int?
    public let malScore: Double?
    public let coverImageRemoteURL: String

    // Extended cached metadata (optional for backwards/forwards schema compatibility)
    public let englishTitle: String?
    public let japaneseTitle: String?
    public let customTitleOverride: String?
    public let synopsis: String?
    public let seasonYear: String?
    public let genres: [String]?
    public let broadcastDayRaw: String?
    public let broadcastTimeUTC: String?

    public init(
        malID: Int,
        title: String,
        watchStatus: String,
        currentEpisodeProgress: Int,
        userRating: Int?,
        personalNotes: String,
        dateAdded: String,
        dateStarted: String?,
        dateCompleted: String?,
        airingStatus: String,
        totalEpisodes: Int?,
        malScore: Double?,
        coverImageRemoteURL: String,
        englishTitle: String? = nil,
        japaneseTitle: String? = nil,
        customTitleOverride: String? = nil,
        synopsis: String? = nil,
        seasonYear: String? = nil,
        genres: [String]? = nil,
        broadcastDayRaw: String? = nil,
        broadcastTimeUTC: String? = nil
    ) {
        self.malID = malID
        self.title = title
        self.watchStatus = watchStatus
        self.currentEpisodeProgress = currentEpisodeProgress
        self.userRating = userRating
        self.personalNotes = personalNotes
        self.dateAdded = dateAdded
        self.dateStarted = dateStarted
        self.dateCompleted = dateCompleted
        self.airingStatus = airingStatus
        self.totalEpisodes = totalEpisodes
        self.malScore = malScore
        self.coverImageRemoteURL = coverImageRemoteURL
        self.englishTitle = englishTitle
        self.japaneseTitle = japaneseTitle
        self.customTitleOverride = customTitleOverride
        self.synopsis = synopsis
        self.seasonYear = seasonYear
        self.genres = genres
        self.broadcastDayRaw = broadcastDayRaw
        self.broadcastTimeUTC = broadcastTimeUTC
    }
}

extension AnimeBackupRecord {
    public static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static let fallbackISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        return fallbackISO8601Formatter.date(from: string)
    }

    public static func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return fallbackISO8601Formatter.string(from: date)
    }
}
