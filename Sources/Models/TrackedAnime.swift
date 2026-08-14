import SwiftData
import Foundation

@Model
public final class TrackedAnime {
    // Primary Key mapping to MyAnimeList ID (Uniqueness managed at application level for CloudKit compatibility)
    public var malID: Int = 0

    // External MAL Metadata Snapshot (Cached locally)
    public var title: String = ""
    public var englishTitle: String? = nil
    public var japaneseTitle: String? = nil
    public var customTitleOverride: String? = nil
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
        englishTitle: String? = nil,
        japaneseTitle: String? = nil,
        customTitleOverride: String? = nil,
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
        self.englishTitle = englishTitle
        self.japaneseTitle = japaneseTitle
        self.customTitleOverride = customTitleOverride
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

    public var seasonYearFormatted: String? {
        guard let seasonYear, !seasonYear.isEmpty else { return nil }
        return AnimeDateFormatter.format(rawDateString: seasonYear)
    }

    // MARK: - State Manipulation Mechanics

    /// Sets the watch status and manages lifecycle timestamps per specification
    public func resetToWatchStatus(_ status: WatchStatus) {
        watchStatusRaw = status.rawValue
        currentEpisodeProgress = 0
        dateAdded = Date()
        statusLastUpdatedAt = Date()
    }

    /// Resolves the displayed title based on user preference (English, Romaji, Native) with graceful fallbacks
    public func displayTitle(for preference: TitleLanguagePreference = .english) -> String {
        if let custom = customTitleOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }

        switch preference {
        case .english:
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"

        case .romaji:
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"

        case .native:
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            return "Untitled Anime"
        }
    }

    /// Returns list of all available title variants with non-empty values
    public var titleVariants: [(preference: TitleLanguagePreference, title: String)] {
        var list: [(TitleLanguagePreference, String)] = []
        if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
            list.append((.english, en))
        }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append((.romaji, title))
        }
        if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
            list.append((.native, jp))
        }
        return list
    }

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

public enum AnimeDateFormatter {
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func ordinalDay(_ day: Int) -> String {
        switch day {
        case 11, 12, 13: return "\(day)th"
        default:
            switch day % 10 {
            case 1: return "\(day)st"
            case 2: return "\(day)nd"
            case 3: return "\(day)rd"
            default: return "\(day)th"
            }
        }
    }

    public static func format(year: Int?, month: Int?, day: Int?) -> String? {
        guard let year, year > 0 else { return nil }
        guard let month, (1...12).contains(month) else {
            return "\(year)"
        }
        let m = monthNames[month - 1]
        guard let day, (1...31).contains(day) else {
            return "\(m) \(year)"
        }
        return "\(ordinalDay(day)) \(m) \(year)"
    }

    public static func format(rawDateString: String?) -> String? {
        guard let raw = rawDateString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "0000-00-00" else {
            return nil
        }
        // If already formatted like "14th Aug 2026", return as is
        if raw.contains("th") || raw.contains("st") || raw.contains("nd") || raw.contains("rd") {
            return raw
        }
        // Check ISO / YYYY-MM-DD format: e.g. "2026-08-14" or "2026-08-14T..."
        let parts = raw.prefix(10).split(separator: "-")
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            return format(year: y, month: m, day: d)
        } else if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) {
            return format(year: y, month: m, day: nil)
        } else if parts.count == 1, let y = Int(parts[0]) {
            return format(year: y, month: nil, day: nil)
        }
        return raw
    }
}

