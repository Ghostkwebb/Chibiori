import Foundation
import SwiftData
import Observation

public struct HydrationProgress: Sendable {
    public let totalToHydrate: Int
    public let hydratedCount: Int
    public let isCompleted: Bool
}

@Observable
@MainActor
public final class MetadataHydrationService {
    public static let shared = MetadataHydrationService()

    public var isHydrating: Bool = false
    public var currentProgress: Double = 0.0 // 0.0 to 1.0
    public var statusMessage: String? = nil

    private let aniList: AniListClient

    public init(aniList: AniListClient = .shared) {
        self.aniList = aniList
    }

    /// Hydrates all TrackedAnime models that have missing cover images, synopses, airing status, or full release dates.
    /// Returns `true` if any library entries were updated.
    @discardableResult
    public func hydrateMissingMetadata(context: ModelContext) async -> Bool {
        guard !isHydrating else { return false }

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        guard let allAnimes = try? context.fetch(fetchDescriptor) else { return false }

        var missingAnimes: [TrackedAnime] = []
        for anime in allAnimes {
            if anime.coverImageRemoteURL.isEmpty ||
               anime.synopsis.isEmpty ||
               anime.airingStatusRaw.isEmpty ||
               (anime.seasonYear == nil && anime.airingEndDate == nil) {
                missingAnimes.append(anime)
            }
        }
        guard !missingAnimes.isEmpty else { return false }

        isHydrating = true
        currentProgress = 0.0
        statusMessage = "Enriching titles, posters & dates for \(missingAnimes.count) anime..."

        var didMutate = false
        let chunkSize = 40
        let chunks = stride(from: 0, to: missingAnimes.count, by: chunkSize).map {
            Array(missingAnimes[$0..<min($0 + chunkSize, missingAnimes.count)])
        }

        var processed = 0

        for (index, chunk) in chunks.enumerated() {
            let malIDs = chunk.map { $0.malID }
            let metadataMap = await fetchBatchMetadata(for: malIDs)

            for anime in chunk {
                if let meta = metadataMap[anime.malID] {
                    if let romaji = meta.title, !romaji.isEmpty {
                        if anime.title.isEmpty || anime.title == anime.englishTitle || anime.title == meta.englishTitle {
                            anime.title = romaji
                            didMutate = true
                        }
                    }
                    if anime.coverImageRemoteURL.isEmpty, let cover = meta.coverURL, !cover.isEmpty {
                        anime.coverImageRemoteURL = cover
                        didMutate = true
                    }
                    if anime.synopsis.isEmpty, let syn = meta.synopsis, !syn.isEmpty {
                        anime.synopsis = syn
                        didMutate = true
                    }
                    if anime.englishTitle == nil, let en = meta.englishTitle, !en.isEmpty {
                        anime.englishTitle = en
                        didMutate = true
                    }
                    if anime.japaneseTitle == nil, let jp = meta.japaneseTitle, !jp.isEmpty {
                        anime.japaneseTitle = jp
                        didMutate = true
                    }
                    if anime.malScore == nil, let score = meta.score, score > 0 {
                        anime.malScore = score
                        didMutate = true
                    }
                    if let status = meta.airingStatusRaw, !status.isEmpty, anime.airingStatusRaw != status {
                        anime.airingStatusRaw = status
                        didMutate = true
                    }
                    if let releaseDate = meta.seasonYear, !releaseDate.isEmpty, anime.seasonYear != releaseDate {
                        anime.seasonYear = releaseDate
                        didMutate = true
                    }
                    if let endDate = meta.airingEndDate, !endDate.isEmpty, anime.airingEndDate != endDate {
                        anime.airingEndDate = endDate
                        didMutate = true
                    }
                    if anime.totalEpisodes == nil, let eps = meta.episodes, eps > 0 {
                        anime.totalEpisodes = eps
                        didMutate = true
                    }
                    if anime.genres.isEmpty, !meta.genres.isEmpty {
                        anime.genres = meta.genres
                        didMutate = true
                    }
                }

                if anime.dubbedLanguages.isEmpty {
                    let dubs = await DubbedLanguageService.shared.offlineDubbedLanguages(malId: anime.malID)
                    if !dubs.isEmpty {
                        anime.dubbedLanguages = dubs.map { $0.name }
                        didMutate = true
                    }
                }
            }

            try? context.save()

            let coversToPrefetch = chunk.compactMap { a -> (Int, String, String?)? in
                guard !a.coverImageRemoteURL.isEmpty else { return nil }
                return (a.malID, a.coverImageRemoteURL, a.coverImageFilename)
            }
            if !coversToPrefetch.isEmpty {
                CoverImageManager.shared.prefetchCovers(items: coversToPrefetch)
            }

            processed += chunk.count
            currentProgress = Double(processed) / Double(missingAnimes.count)
            statusMessage = "Updated \(processed) of \(missingAnimes.count) anime..."

            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        statusMessage = "All \(missingAnimes.count) anime enriched successfully!"
        isHydrating = false

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !self.isHydrating {
                self.statusMessage = nil
            }
        }

        return didMutate
    }

    /// Automatically checks airing, upcoming, or incomplete-count anime in library to sync status changes and episode counts.
    /// Returns `true` if any library entries were updated.
    @discardableResult
    public func syncActiveAiringStatuses(context: ModelContext, forceAll: Bool = false) async -> Bool {
        guard !isHydrating else { return false }

        let lastSyncKey = "chibiori_last_airing_sync_timestamp"
        if !forceAll {
            let lastSync = UserDefaults.standard.double(forKey: lastSyncKey)
            let now = Date().timeIntervalSince1970
            if now - lastSync < 43200 { // 12-hour throttle
                return false
            }
        }

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        guard let allAnimes = try? context.fetch(fetchDescriptor) else { return false }

        let activeAnimes = allAnimes.filter { anime in
            guard anime.malID > 0 else { return false }
            if forceAll { return true }
            let isNotFinished = anime.airingStatus != .finishedAiring
            let hasUnknownEpisodes = (anime.totalEpisodes == nil || anime.totalEpisodes == 0)
            let isWatchingOrPlan = (anime.watchStatus == .watching || anime.watchStatus == .planToWatch)
            return isNotFinished || (isWatchingOrPlan && hasUnknownEpisodes)
        }

        guard !activeAnimes.isEmpty else { return false }

        isHydrating = true
        statusMessage = "Checking airing statuses for \(activeAnimes.count) active anime..."

        var didMutate = false
        let chunkSize = 45
        let chunks = stride(from: 0, to: activeAnimes.count, by: chunkSize).map {
            Array(activeAnimes[$0..<min($0 + chunkSize, activeAnimes.count)])
        }

        for (index, chunk) in chunks.enumerated() {
            let malIDs = chunk.map { $0.malID }
            let metadataMap = await fetchBatchMetadata(for: malIDs)

            for anime in chunk {
                guard let meta = metadataMap[anime.malID] else { continue }
                if let status = meta.airingStatusRaw, !status.isEmpty {
                    let standardized: String
                    if status.uppercased() == "FINISHED" || status.lowercased().contains("finished") {
                        standardized = "Finished Airing"
                    } else if status.uppercased() == "RELEASING" || status.lowercased().contains("airing") {
                        standardized = "Currently Airing"
                    } else if status.uppercased() == "NOT_YET_RELEASED" || status.lowercased().contains("not") {
                        standardized = "Not Yet Aired"
                    } else {
                        standardized = status
                    }
                    if anime.airingStatusRaw != standardized {
                        anime.airingStatusRaw = standardized
                        didMutate = true
                    }
                }

                if let eps = meta.episodes, eps > 0, anime.totalEpisodes != eps {
                    anime.totalEpisodes = eps
                    didMutate = true
                }

                if let score = meta.score, score > 0, anime.malScore != score {
                    anime.malScore = score
                    didMutate = true
                }

                if let releaseDate = meta.seasonYear, !releaseDate.isEmpty, anime.seasonYear != releaseDate {
                    anime.seasonYear = releaseDate
                    didMutate = true
                }

                if let endDate = meta.airingEndDate, !endDate.isEmpty, anime.airingEndDate != endDate {
                    anime.airingEndDate = endDate
                    didMutate = true
                }

                if anime.englishTitle == nil, let en = meta.englishTitle, !en.isEmpty {
                    anime.englishTitle = en
                    didMutate = true
                }
                if anime.japaneseTitle == nil, let jp = meta.japaneseTitle, !jp.isEmpty {
                    anime.japaneseTitle = jp
                    didMutate = true
                }
                if anime.synopsis.isEmpty, let syn = meta.synopsis, !syn.isEmpty {
                    anime.synopsis = syn
                    didMutate = true
                }
            }

            try? context.save()

            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        isHydrating = false
        statusMessage = nil
        return didMutate
    }

    /// Refreshes all details for a single anime on-demand (e.g., from the Inspector sidebar).
    public func refreshAnimeMetadata(anime: TrackedAnime, context: ModelContext) async {
        guard anime.malID > 0 else { return }

        let metadataMap = await fetchBatchMetadata(for: [anime.malID])
        if let meta = metadataMap[anime.malID] {
            if let status = meta.airingStatusRaw, !status.isEmpty {
                if status.uppercased() == "FINISHED" || status.lowercased().contains("finished") {
                    anime.airingStatusRaw = "Finished Airing"
                } else if status.uppercased() == "RELEASING" || status.lowercased().contains("airing") {
                    anime.airingStatusRaw = "Currently Airing"
                } else if status.uppercased() == "NOT_YET_RELEASED" || status.lowercased().contains("not") {
                    anime.airingStatusRaw = "Not Yet Aired"
                } else {
                    anime.airingStatusRaw = status
                }
            }

            if let eps = meta.episodes, eps > 0 { anime.totalEpisodes = eps }
            if let score = meta.score, score > 0 { anime.malScore = score }
            if let releaseDate = meta.seasonYear, !releaseDate.isEmpty { anime.seasonYear = releaseDate }
            if let endDate = meta.airingEndDate, !endDate.isEmpty { anime.airingEndDate = endDate }
            if let syn = meta.synopsis, !syn.isEmpty { anime.synopsis = syn }
            if let romaji = meta.title, !romaji.isEmpty { anime.title = romaji }
            if let en = meta.englishTitle, !en.isEmpty { anime.englishTitle = en }
            if let jp = meta.japaneseTitle, !jp.isEmpty { anime.japaneseTitle = jp }
            if let cover = meta.coverURL, !cover.isEmpty { anime.coverImageRemoteURL = cover }
            if !meta.genres.isEmpty { anime.genres = meta.genres }

            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID, forceRefresh: true)
            if !dubs.isEmpty {
                anime.dubbedLanguages = dubs.map { $0.name }
            }

            try? context.save()
            return
        }

        if let dto = try? await JikanAPIService.shared.fetchAnimeDetails(id: anime.malID) {
            if let status = dto.status, !status.isEmpty { anime.airingStatusRaw = status }
            if let eps = dto.episodes, eps > 0 { anime.totalEpisodes = eps }
            if let score = dto.score, score > 0 { anime.malScore = score }
            if let syn = dto.synopsis, !syn.isEmpty { anime.synopsis = syn }
            if !dto.title.isEmpty { anime.title = dto.title }
            if let en = dto.titleEnglish, !en.isEmpty { anime.englishTitle = en }
            if let jp = dto.titleJapanese, !jp.isEmpty { anime.japaneseTitle = jp }
            if let release = dto.startDateFormatted, !release.isEmpty { anime.seasonYear = release }
            if let endDate = dto.airingEndDateFormatted, !endDate.isEmpty { anime.airingEndDate = endDate }
            if let genres = dto.genres, !genres.isEmpty { anime.genres = genres.map { $0.name } }
            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID, forceRefresh: true)
            if !dubs.isEmpty {
                anime.dubbedLanguages = dubs.map { $0.name }
            }
            try? context.save()
        }
    }

    public static func stripHTMLTags(from string: String?) -> String? {
        HTMLCleaner.strip(from: string)
    }

    private struct FetchedMetadata {
        let malID: Int
        let title: String?
        let englishTitle: String?
        let japaneseTitle: String?
        let coverURL: String?
        let synopsis: String?
        let score: Double?
        let airingStatusRaw: String?
        let seasonYear: String?
        let airingEndDate: String?
        let episodes: Int?
        let genres: [String]
    }

    private func fetchBatchMetadata(for malIDs: [Int]) async -> [Int: FetchedMetadata] {
        let mediaList = await aniList.fetchBatchMetadata(malIDs: malIDs)
        var map: [Int: FetchedMetadata] = [:]

        for item in mediaList {
            guard let idMal = item.idMal else { continue }

            let coverLarge = item.coverImage?.large ?? item.coverImage?.extraLarge
            let formattedDate = AnimeDateFormatter.format(
                year: item.startDate?.year,
                month: item.startDate?.month,
                day: item.startDate?.day
            )
            let formattedEndDate = AnimeDateFormatter.format(
                year: item.endDate?.year,
                month: item.endDate?.month,
                day: item.endDate?.day
            )

            var fallbackDate: String? = nil
            if let s = item.season?.capitalized, let y = item.seasonYear {
                fallbackDate = "\(s) \(y)"
            } else if let y = item.seasonYear {
                fallbackDate = "\(y)"
            }

            let avgScore = (item.averageScore ?? 0) / 10.0

            map[idMal] = FetchedMetadata(
                malID: idMal,
                title: item.title?.romaji,
                englishTitle: item.resolvedEnglishTitle,
                japaneseTitle: item.title?.native,
                coverURL: coverLarge,
                synopsis: HTMLCleaner.strip(from: item.description),
                score: avgScore > 0 ? avgScore : nil,
                airingStatusRaw: item.status,
                seasonYear: formattedDate ?? fallbackDate,
                airingEndDate: formattedEndDate,
                episodes: item.episodes,
                genres: item.genres ?? []
            )
        }

        return map
    }
}
