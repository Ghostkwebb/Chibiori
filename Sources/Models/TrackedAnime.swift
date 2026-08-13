import SwiftData
import Foundation

@Model
public final class TrackedAnime {
    // Primary Key mapping to MyAnimeList ID (Uniqueness managed at application level for CloudKit compatibility)
    public var malID: Int = 0

    // External MAL Metadata Snapshot (Cached locally)
    public var title: String = ""
    public var japaneseTitle: String? = nil
    public var synopsis: String = ""
    public var coverImageFilename: String? = nil // Relative filename in Local Storage
    public var coverImageRemoteURL: String = ""
    public var bannerImageRemoteURL: String? = nil // Cinematic banner backdrop
    public var airingStatusRaw: String = "Finished Airing" // "Currently Airing", "Finished Airing", "Not Yet Airing"
    public var totalEpisodes: Int? = nil // Nil for unknown / ongoing
    public var broadcastDayRaw: String? = nil // e.g. "Mondays"
    public var broadcastTimeUTC: String? = nil // e.g. "15:00"
    public var malScore: Double? = nil
    public var seasonYear: String? = nil // e.g. "Spring 2026"
    public var genres: [String] = [] // Genre tags array

    // User Local State (Immutable / User Controlled)
    public var watchStatusRaw: String = "planToWatch" // "planToWatch", "watching", "completed", "onHold", "dropped"
    public var currentEpisodeProgress: Int = 0
    public var userRating: Int? = nil // 1 to 10
    public var personalNotes: String = ""

    // Timestamps
    public var dateAdded: Date = Date() // Refreshed when re-added to queue
    public var dateStarted: Date? = nil // Recorded on shift to "watching"
    public var dateCompleted: Date? = nil // Recorded on shift to "completed"
    public var statusLastUpdatedAt: Date = Date() // Recorded on any status shift

    public init(
        malID: Int,
        title: String,
        synopsis: String,
        coverImageRemoteURL: String,
        airingStatusRaw: String,
        japaneseTitle: String? = nil,
        totalEpisodes: Int? = nil,
        broadcastDayRaw: String? = nil,
        broadcastTimeUTC: String? = nil,
        malScore: Double? = nil,
        seasonYear: String? = nil,
        genres: [String] = [],
        bannerImageRemoteURL: String? = nil
    ) {
        self.malID = malID
        self.title = title
        self.synopsis = synopsis
        self.coverImageRemoteURL = coverImageRemoteURL
        self.bannerImageRemoteURL = bannerImageRemoteURL
        self.airingStatusRaw = airingStatusRaw
        self.japaneseTitle = japaneseTitle
        self.totalEpisodes = totalEpisodes
        self.broadcastDayRaw = broadcastDayRaw
        self.broadcastTimeUTC = broadcastTimeUTC
        self.malScore = malScore
        self.seasonYear = seasonYear
        self.genres = genres

        self.watchStatusRaw = WatchStatus.planToWatch.rawValue
        self.currentEpisodeProgress = 0
        self.personalNotes = ""
        self.userRating = nil
        self.dateAdded = Date()
        self.statusLastUpdatedAt = Date()
    }

    // MARK: - Computed Properties

    public var watchStatus: WatchStatus {
        get {
            WatchStatus(rawValue: watchStatusRaw) ?? .planToWatch
        }
        set {
            setWatchStatus(newValue)
        }
    }

    public var airingStatus: AiringStatus? {
        AiringStatus.from(raw: airingStatusRaw)
    }

    // MARK: - State Manipulation Mechanics

    /// Sets the watch status and manages lifecycle timestamps per specification
    public func setWatchStatus(_ newStatus: WatchStatus) {
        guard watchStatusRaw != newStatus.rawValue else { return }

        watchStatusRaw = newStatus.rawValue
        statusLastUpdatedAt = Date()

        switch newStatus {
        case .watching:
            if dateStarted == nil {
                dateStarted = Date()
            }
        case .completed:
            if dateCompleted == nil {
                dateCompleted = Date()
            }
            if let total = totalEpisodes, currentEpisodeProgress < total {
                currentEpisodeProgress = total
            }
        case .planToWatch, .onHold, .dropped:
            break
        }
    }

    /// Re-queues the anime by refreshing `dateAdded` to Date.now while preserving historical dates
    public func reQueue() {
        self.dateAdded = Date()
        self.statusLastUpdatedAt = Date()
        self.watchStatusRaw = WatchStatus.planToWatch.rawValue
    }

    /// Increments episode progress with auto-completion trigger if reaching total episodes
    public func incrementProgress() {
        if let total = totalEpisodes {
            guard currentEpisodeProgress < total else { return }
            currentEpisodeProgress += 1
            statusLastUpdatedAt = Date()
            if currentEpisodeProgress == total {
                setWatchStatus(.completed)
            } else if watchStatus != .watching && watchStatus != .completed {
                setWatchStatus(.watching)
            }
        } else {
            currentEpisodeProgress += 1
            statusLastUpdatedAt = Date()
            if watchStatus != .watching && watchStatus != .completed {
                setWatchStatus(.watching)
            }
        }
    }

    /// Decrements episode progress safely
    public func decrementProgress() {
        guard currentEpisodeProgress > 0 else { return }
        currentEpisodeProgress -= 1
        statusLastUpdatedAt = Date()
    }
}
