import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class LibraryStore {
    private let modelContext: ModelContext
    private let cloudSync: CloudSyncService
    private let scoreService: MultiSiteScoreService
    private var notesSaveTask: Task<Void, Never>?

    public private(set) var allAnime: [TrackedAnime] = []
    public private(set) var animeByMalID: [Int: TrackedAnime] = [:]
    public private(set) var animeByID: [PersistentIdentifier: TrackedAnime] = [:]
    public private(set) var siteScoresByMalID: [Int: AnimeSiteScores] = [:]
    public private(set) var statusCounts: [WatchStatus: Int] = [:]
    public private(set) var totalEpisodesWatched: Int = 0
    public private(set) var missingCoversCount: Int = 0
    public private(set) var revision: Int = 0

    public init(
        modelContext: ModelContext,
        cloudSync: CloudSyncService? = nil,
        scoreService: MultiSiteScoreService? = nil
    ) {
        self.modelContext = modelContext
        self.cloudSync = cloudSync ?? .shared
        self.scoreService = scoreService ?? .shared
        reload(notifyCloudSync: false)
        Task { @MainActor [weak self] in
            await self?.loadCachedSiteScores()
        }
    }

    public func loadCachedSiteScores() async {
        let cached = await scoreService.allCachedScores()
        guard !cached.isEmpty else { return }
        self.siteScoresByMalID = cached
        self.revision &+= 1
    }

    /// Stores multi-website score cache for an anime and promotes verified MAL scores to `TrackedAnime.malScore`.
    public func applySiteScores(_ scores: AnimeSiteScores, for anime: TrackedAnime? = nil) {
        let previous = siteScoresByMalID[scores.malID]
        siteScoresByMalID[scores.malID] = scores

        let target = anime ?? animeByMalID[scores.malID]
        if let target, let verifiedMAL = scores.malScore, verifiedMAL > 0, target.malScore != verifiedMAL {
            target.malScore = verifiedMAL
            commitAndNotify()
        } else if previous != scores {
            revision &+= 1
        }
    }

    /// Returns the preferred score badge ordered by user choice (`Auto`, `MAL`, `AniList`, `Shikimori`, `Kitsu`).
    public func primaryScoreDisplay(
        for anime: TrackedAnime,
        preference: ScoreDisplayPreference = .auto
    ) -> (source: ScoreSource, score: Double)? {
        if let badge = siteScoresByMalID[anime.malID]?.badge(for: preference) {
            return badge
        }
        if let fallback = anime.malScore, fallback > 0 {
            return (.aniList, fallback)
        }
        return nil
    }

    /// Background batch-prefetch of missing scores, streaming chunks into the UI as they arrive.
    public func prefetchScores(for malIDs: [Int], preference: ScoreDisplayPreference) async {
        if siteScoresByMalID.isEmpty {
            await loadCachedSiteScores()
        }
        _ = await scoreService.prefetchBatchScores(for: malIDs, preference: preference) { batch in
            await MainActor.run {
                self.mergePrefetchedBatch(batch)
            }
        }
    }

    private func mergePrefetchedBatch(_ batch: [Int: AnimeSiteScores]) {
        guard !batch.isEmpty else { return }
        var mutatedModels = false
        for (malID, scores) in batch {
            siteScoresByMalID[malID] = scores
            if let target = animeByMalID[malID],
               let malScore = scores.malScore, malScore > 0,
               target.malScore != malScore {
                target.malScore = malScore
                mutatedModels = true
            }
        }

        if mutatedModels {
            commitAndNotify()
        } else {
            revision &+= 1
        }
    }

    /// Re-fetches the library from SwiftData and rebuilds O(1) lookup indexes and sidebar counts.
    public func reload(notifyCloudSync: Bool = false) {
        let descriptor = FetchDescriptor<TrackedAnime>(
            sortBy: [SortDescriptor(\TrackedAnime.dateAdded, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        self.allAnime = fetched
        rebuildIndexes()
        revision &+= 1
        if notifyCloudSync {
            cloudSync.scheduleAutoCloudBackup(from: allAnime)
        }
    }

    private func rebuildIndexes() {
        var malMap: [Int: TrackedAnime] = [:]
        malMap.reserveCapacity(allAnime.count)
        var idMap: [PersistentIdentifier: TrackedAnime] = [:]
        idMap.reserveCapacity(allAnime.count)
        var counts: [WatchStatus: Int] = [:]
        counts.reserveCapacity(WatchStatus.allCases.count)
        var episodesSum = 0
        var missingCovers = 0

        for anime in allAnime {
            if anime.malID != 0, malMap[anime.malID] == nil {
                malMap[anime.malID] = anime
            }
            idMap[anime.persistentModelID] = anime
            counts[anime.watchStatus, default: 0] += 1
            episodesSum += anime.currentEpisodeProgress
            if anime.coverImageRemoteURL.isEmpty {
                missingCovers += 1
            }
        }

        self.animeByMalID = malMap
        self.animeByID = idMap
        self.statusCounts = counts
        self.totalEpisodesWatched = episodesSum
        self.missingCoversCount = missingCovers
    }

    private func commitAndNotify(needsResort: Bool = false) {
        try? modelContext.save()
        if needsResort {
            allAnime.sort { $0.dateAdded > $1.dateAdded }
        }
        rebuildIndexes()
        revision &+= 1
        cloudSync.scheduleAutoCloudBackup(from: allAnime)
    }

    // MARK: - Lookups & Filtering

    public func anime(for id: PersistentIdentifier?) -> TrackedAnime? {
        guard let id else { return nil }
        return animeByID[id]
    }

    public func anime(forMalID malID: Int) -> TrackedAnime? {
        guard malID != 0 else { return nil }
        return animeByMalID[malID]
    }

    public func findMatchingTracked(malID: Int, title: String, englishTitle: String?) -> TrackedAnime? {
        if malID != 0, let match = animeByMalID[malID] {
            return match
        }
        let lowerTitle = title.lowercased()
        let lowerEn = englishTitle?.lowercased()
        return allAnime.first { tracked in
            tracked.title.lowercased() == lowerTitle ||
            (lowerEn != nil && tracked.englishTitle?.lowercased() == lowerEn)
        }
    }

    public func filteredAnime(
        status: WatchStatus?,
        airing: AiringStatus?,
        query: String,
        sortOption: LibrarySortOption,
        titlePreference: TitleLanguagePreference,
        scorePreference: ScoreDisplayPreference = .auto
    ) -> [TrackedAnime] {
        _ = revision
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !trimmedQuery.isEmpty

        var list = allAnime.filter { anime in
            if let status, anime.watchStatus != status { return false }
            if let airing, anime.airingStatus != airing { return false }
            if hasQuery {
                let matches = anime.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                    (anime.englishTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                    (anime.japaneseTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                    (anime.customTitleOverride?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                    anime.genres.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })
                if !matches { return false }
            }
            return true
        }

        switch sortOption {
        case .dateAddedDesc:
            if status == .completed {
                list.sort { ($0.dateCompleted ?? $0.statusLastUpdatedAt) > ($1.dateCompleted ?? $1.statusLastUpdatedAt) }
            } else {
                list.sort { $0.dateAdded > $1.dateAdded }
            }
        case .dateAddedAsc:
            if status == .completed {
                list.sort { ($0.dateCompleted ?? $0.statusLastUpdatedAt) < ($1.dateCompleted ?? $1.statusLastUpdatedAt) }
            } else {
                list.sort { $0.dateAdded < $1.dateAdded }
            }
        case .titleAsc:
            list.sort {
                $0.displayTitle(for: titlePreference)
                    .localizedCaseInsensitiveCompare($1.displayTitle(for: titlePreference)) == .orderedAscending
            }
        case .scoreDesc:
            list.sort {
                let s0 = primaryScoreDisplay(for: $0, preference: scorePreference)?.score ?? 0
                let s1 = primaryScoreDisplay(for: $1, preference: scorePreference)?.score ?? 0
                if s0 != s1 {
                    return s0 > s1
                }
                return $0.dateAdded > $1.dateAdded
            }
        case .progressDesc:
            list.sort { $0.currentEpisodeProgress > $1.currentEpisodeProgress }
        case .lastUpdatedDesc:
            list.sort { $0.statusLastUpdatedAt > $1.statusLastUpdatedAt }
        }

        return list
    }

    // MARK: - Create / Deduplicate

    @discardableResult
    public func addOrUpdate(
        from dto: JikanAnimeDTO,
        status: WatchStatus,
        dubbedLanguages: [String] = []
    ) -> TrackedAnime {
        if dto.malId != 0, let existing = animeByMalID[dto.malId] {
            if !dubbedLanguages.isEmpty && existing.dubbedLanguages.isEmpty {
                existing.dubbedLanguages = dubbedLanguages
            }
            setWatchStatus(status, for: existing)
            return existing
        }

        let anime = TrackedAnime(
            malID: dto.malId,
            title: dto.title,
            synopsis: dto.synopsis ?? "",
            coverImageRemoteURL: dto.coverImageURL,
            airingStatusRaw: dto.status ?? "Finished Airing",
            englishTitle: dto.titleEnglish,
            japaneseTitle: dto.titleJapanese,
            totalEpisodes: dto.episodes,
            broadcastDayRaw: dto.broadcast?.day,
            broadcastTimeUTC: dto.broadcast?.time,
            malScore: dto.score,
            seasonYear: dto.startDateFormatted ?? dto.seasonYearFormatted,
            airingEndDate: dto.airingEndDateFormatted,
            genres: dto.genreNames,
            dubbedLanguages: dubbedLanguages
        )
        anime.setWatchStatus(status)
        insertAndCacheCover(anime)
        return anime
    }

    @discardableResult
    public func addOrUpdate(from item: RelatedAnimeItem, status: WatchStatus) -> TrackedAnime {
        if item.malID != 0, let existing = animeByMalID[item.malID] {
            setWatchStatus(status, for: existing)
            return existing
        }

        let yearStr = item.seasonYear.map { String($0) }
        let anime = TrackedAnime(
            malID: item.malID,
            title: item.title,
            synopsis: item.synopsis ?? "",
            coverImageRemoteURL: item.coverImageURL ?? "",
            airingStatusRaw: item.status ?? "Finished Airing",
            englishTitle: item.englishTitle,
            japaneseTitle: item.japaneseTitle,
            totalEpisodes: item.episodes,
            seasonYear: yearStr
        )
        anime.setWatchStatus(status)
        insertAndCacheCover(anime)
        return anime
    }

    @discardableResult
    public func addOrUpdate(from alert: SequelAlertItem, status: WatchStatus = .planToWatch) -> TrackedAnime {
        if alert.sequelMalId != 0, let existing = animeByMalID[alert.sequelMalId] {
            setWatchStatus(status, for: existing)
            return existing
        }

        let anime = TrackedAnime(
            malID: alert.sequelMalId,
            title: alert.sequelTitle,
            synopsis: alert.synopsis ?? "",
            coverImageRemoteURL: alert.sequelCoverImageURL,
            airingStatusRaw: alert.sequelStatus == "RELEASING" ? "Currently Airing" : "Not Yet Airing",
            englishTitle: alert.sequelEnglishTitle,
            japaneseTitle: alert.sequelJapaneseTitle,
            seasonYear: alert.airingSeasonYear
        )
        anime.setWatchStatus(status)
        anime.personalNotes = "Automatically added from Sequel Alert (Completed: \(alert.parentTitle))"
        insertAndCacheCover(anime)
        return anime
    }

    private func insertAndCacheCover(_ anime: TrackedAnime) {
        modelContext.insert(anime)
        allAnime.insert(anime, at: 0)
        commitAndNotify(needsResort: true)

        let malID = anime.malID
        let remoteURL = anime.coverImageRemoteURL
        if !remoteURL.isEmpty {
            Task { @MainActor in
                let (_, filename) = await CoverImageManager.shared.loadImage(
                    malID: malID,
                    remoteURLString: remoteURL
                )
                if let filename, anime.coverImageFilename != filename {
                    anime.coverImageFilename = filename
                    try? self.modelContext.save()
                }
            }
        }
    }

    // MARK: - Mutations

    public func setWatchStatus(_ status: WatchStatus, for anime: TrackedAnime) {
        anime.setWatchStatus(status)
        commitAndNotify()
    }

    public func incrementProgress(for anime: TrackedAnime) {
        anime.incrementProgress()
        commitAndNotify()
    }

    public func decrementProgress(for anime: TrackedAnime) {
        anime.decrementProgress()
        commitAndNotify()
    }

    public func finish(_ anime: TrackedAnime) {
        if let total = anime.totalEpisodes, anime.currentEpisodeProgress < total {
            anime.currentEpisodeProgress = total
        }
        anime.setWatchStatus(.completed)
        commitAndNotify()
    }

    public func reQueue(_ anime: TrackedAnime) {
        anime.reQueue()
        commitAndNotify(needsResort: true)
    }

    public func setRating(_ rating: Int?, for anime: TrackedAnime) {
        anime.userRating = rating
        anime.statusLastUpdatedAt = Date()
        commitAndNotify()
    }

    public func setCustomTitle(_ customTitle: String?, for anime: TrackedAnime) {
        let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        anime.customTitleOverride = (trimmed?.isEmpty == false) ? trimmed : nil
        anime.statusLastUpdatedAt = Date()
        commitAndNotify()
    }

    public func scheduleNotesSave(for anime: TrackedAnime) {
        anime.statusLastUpdatedAt = Date()
        notesSaveTask?.cancel()
        notesSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            try? self.modelContext.save()
            self.cloudSync.scheduleAutoCloudBackup(from: self.allAnime)
        }
    }

    public func toggleDubbedLanguage(_ lang: DubbedLanguage, for anime: TrackedAnime) {
        if let index = anime.dubbedLanguages.firstIndex(where: { DubbedLanguage.resolve(from: $0).code == lang.code }) {
            anime.dubbedLanguages.remove(at: index)
        } else {
            anime.dubbedLanguages.append(lang.name)
        }
        commitAndNotify()
    }

    public func addCustomDubbedLanguage(_ raw: String, for anime: TrackedAnime) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !anime.dubbedLanguages.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return }
        anime.dubbedLanguages.append(trimmed)
        commitAndNotify()
    }

    public func mergeDubbedLanguages(_ newNames: [String], for anime: TrackedAnime) {
        let existingLower = Set(anime.dubbedLanguages.map { $0.lowercased() })
        guard anime.dubbedLanguages.isEmpty || (!existingLower.contains("english") && newNames.contains("English")) else {
            return
        }
        var merged = anime.dubbedLanguages
        for name in newNames where !existingLower.contains(name.lowercased()) {
            merged.append(name)
        }
        if merged != anime.dubbedLanguages {
            anime.dubbedLanguages = merged
            commitAndNotify()
        }
    }

    public func replaceDubbedLanguages(_ names: [String], for anime: TrackedAnime) {
        if anime.dubbedLanguages != names {
            anime.dubbedLanguages = names
            commitAndNotify()
        }
    }

    public func delete(_ anime: TrackedAnime) {
        let targetID = anime.persistentModelID
        modelContext.delete(anime)
        allAnime.removeAll { $0.persistentModelID == targetID }
        commitAndNotify()
    }

    public func saveNow() {
        try? modelContext.save()
    }
}
