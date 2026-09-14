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

    private init() {}

    /// Hydrates all TrackedAnime models that have missing cover images, synopses, airing status, or full release dates
    public func hydrateMissingMetadata(context: ModelContext) async {
        guard !isHydrating else { return }

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        guard let allAnimes = try? context.fetch(fetchDescriptor) else { return }

        var missingAnimes: [TrackedAnime] = []
        for anime in allAnimes {
            let hasEnglish = anime.dubbedLanguages.contains { $0.caseInsensitiveCompare("English") == .orderedSame }
            let isVerifiedEnglish = await DubbedLanguageService.shared.hasVerifiedEnglishDub(malId: anime.malID)
            let needsEnglishDub = !hasEnglish && isVerifiedEnglish

            if anime.coverImageRemoteURL.isEmpty ||
               anime.synopsis.isEmpty ||
               anime.airingStatusRaw.isEmpty ||
               anime.seasonYear == nil ||
               anime.airingStatus == nil ||
               anime.totalEpisodes == nil ||
               anime.englishTitle == nil ||
               anime.japaneseTitle == nil ||
               (anime.airingStatus == .finishedAiring && anime.airingEndDate == nil) ||
               (anime.englishTitle != nil && anime.title == anime.englishTitle) ||
               anime.dubbedLanguages.isEmpty ||
               needsEnglishDub {
                missingAnimes.append(anime)
            }
        }
        guard !missingAnimes.isEmpty else { return }

        isHydrating = true
        currentProgress = 0.0
        statusMessage = "Enriching titles, posters & dates for \(missingAnimes.count) anime..."

        // Group into chunks of 40 IDs for AniList GraphQL batch queries
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
                        }
                    }
                    if anime.coverImageRemoteURL.isEmpty, let cover = meta.coverURL, !cover.isEmpty {
                        anime.coverImageRemoteURL = cover
                    }
                    if anime.synopsis.isEmpty, let syn = meta.synopsis, !syn.isEmpty {
                        anime.synopsis = syn
                    }
                    if anime.englishTitle == nil, let en = meta.englishTitle, !en.isEmpty {
                        anime.englishTitle = en
                    }
                    if anime.japaneseTitle == nil, let jp = meta.japaneseTitle, !jp.isEmpty {
                        anime.japaneseTitle = jp
                    }
                    if anime.malScore == nil, let score = meta.score, score > 0 {
                        anime.malScore = score
                    }
                    if let status = meta.airingStatusRaw, !status.isEmpty {
                        anime.airingStatusRaw = status
                    }
                    if let releaseDate = meta.seasonYear, !releaseDate.isEmpty {
                        anime.seasonYear = releaseDate
                    }
                    if let endDate = meta.airingEndDate, !endDate.isEmpty {
                        anime.airingEndDate = endDate
                    }
                    if anime.totalEpisodes == nil, let eps = meta.episodes, eps > 0 {
                        anime.totalEpisodes = eps
                    }
                    if anime.genres.isEmpty, !meta.genres.isEmpty {
                        anime.genres = meta.genres
                    }
                }

                let hasEnglish = anime.dubbedLanguages.contains { $0.caseInsensitiveCompare("English") == .orderedSame }
                let isVerifiedEnglish = await DubbedLanguageService.shared.hasVerifiedEnglishDub(malId: anime.malID)
                let needsEnglish = !hasEnglish && isVerifiedEnglish
                if anime.dubbedLanguages.isEmpty || needsEnglish {
                    let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID)
                    if !dubs.isEmpty {
                        let existingLower = Set(anime.dubbedLanguages.map { $0.lowercased() })
                        let newNames = dubs.map { $0.name }
                        var merged = anime.dubbedLanguages
                        for name in newNames where !existingLower.contains(name.lowercased()) {
                            merged.append(name)
                        }
                        if merged != anime.dubbedLanguages {
                            anime.dubbedLanguages = merged
                        }
                    }
                }
            }

            try? context.save()

            processed += chunk.count
            currentProgress = Double(processed) / Double(missingAnimes.count)
            statusMessage = "Updated \(processed) of \(missingAnimes.count) anime..."

            if index < chunks.count - 1 {
                // Gentle delay between batches to respect rate limits
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        statusMessage = "All \(missingAnimes.count) anime enriched successfully!"
        isHydrating = false

        // Clear status message after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !self.isHydrating {
                self.statusMessage = nil
            }
        }
    }

    /// Automatically checks all currently airing, upcoming, or uncompleted-count anime in your library to sync status changes (e.g. Airing -> Finished) and episode counts
    public func syncActiveAiringStatuses(context: ModelContext, forceAll: Bool = false) async {
        guard !isHydrating else { return }

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        guard let allAnimes = try? context.fetch(fetchDescriptor) else { return }

        // Filter anime that may have changed airing state:
        // - AiringStatus is currently airing, upcoming/not yet aired, or unknown
        // - Total episodes is unknown/nil or 0
        // - Or currently in Watching / Plan to Watch list
        let activeAnimes = allAnimes.filter { anime in
            guard anime.malID > 0 else { return false }
            if forceAll { return true }
            let isNotFinished = anime.airingStatus != .finishedAiring
            let hasUnknownEpisodes = (anime.totalEpisodes == nil || anime.totalEpisodes == 0)
            let isWatchingOrPlan = (anime.watchStatus == .watching || anime.watchStatus == .planToWatch)
            return isNotFinished || (isWatchingOrPlan && hasUnknownEpisodes)
        }

        guard !activeAnimes.isEmpty else { return }

        isHydrating = true
        statusMessage = "Checking airing statuses for \(activeAnimes.count) active anime..."

        let chunkSize = 45
        let chunks = stride(from: 0, to: activeAnimes.count, by: chunkSize).map {
            Array(activeAnimes[$0..<min($0 + chunkSize, activeAnimes.count)])
        }

        for (index, chunk) in chunks.enumerated() {
            let malIDs = chunk.map { $0.malID }
            let metadataMap = await fetchBatchMetadata(for: malIDs)

            for anime in chunk {
                if let meta = metadataMap[anime.malID] {
                    if let status = meta.airingStatusRaw, !status.isEmpty {
                        // If AniList returns FINISHED, RELEASING, or NOT_YET_RELEASED, standardize it
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

                    if let eps = meta.episodes, eps > 0 {
                        anime.totalEpisodes = eps
                    }

                    if let score = meta.score, score > 0 {
                        anime.malScore = score
                    }

                    if let releaseDate = meta.seasonYear, !releaseDate.isEmpty {
                        anime.seasonYear = releaseDate
                    }

                    if let endDate = meta.airingEndDate, !endDate.isEmpty {
                        anime.airingEndDate = endDate
                    }

                    if anime.englishTitle == nil, let en = meta.englishTitle, !en.isEmpty {
                        anime.englishTitle = en
                    }
                    if anime.japaneseTitle == nil, let jp = meta.japaneseTitle, !jp.isEmpty {
                        anime.japaneseTitle = jp
                    }
                    if anime.synopsis.isEmpty, let syn = meta.synopsis, !syn.isEmpty {
                        anime.synopsis = syn
                    }
                }
            }

            try? context.save()

            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        isHydrating = false
        statusMessage = nil
    }

    /// Refreshes all details for a single anime on-demand (e.g. from the Inspector sidebar)
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

            if let eps = meta.episodes, eps > 0 {
                anime.totalEpisodes = eps
            }

            if let score = meta.score, score > 0 {
                anime.malScore = score
            }

            if let releaseDate = meta.seasonYear, !releaseDate.isEmpty {
                anime.seasonYear = releaseDate
            }

            if let endDate = meta.airingEndDate, !endDate.isEmpty {
                anime.airingEndDate = endDate
            }

            if let syn = meta.synopsis, !syn.isEmpty {
                anime.synopsis = syn
            }

            if let romaji = meta.title, !romaji.isEmpty {
                anime.title = romaji
            }

            if let en = meta.englishTitle, !en.isEmpty {
                anime.englishTitle = en
            }

            if let jp = meta.japaneseTitle, !jp.isEmpty {
                anime.japaneseTitle = jp
            }

            if let cover = meta.coverURL, !cover.isEmpty {
                anime.coverImageRemoteURL = cover
            }

            if !meta.genres.isEmpty {
                anime.genres = meta.genres
            }

            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID, forceRefresh: true)
            if !dubs.isEmpty {
                anime.dubbedLanguages = dubs.map { $0.name }
            }

            try? context.save()
            return
        }

        // Fallback to Jikan REST API if AniList GraphQL did not have it
        if let dto = try? await JikanAPIService.shared.fetchAnimeDetails(id: anime.malID) {
            if let status = dto.status, !status.isEmpty {
                anime.airingStatusRaw = status
            }
            if let eps = dto.episodes, eps > 0 {
                anime.totalEpisodes = eps
            }
            if let score = dto.score, score > 0 {
                anime.malScore = score
            }
            if let syn = dto.synopsis, !syn.isEmpty {
                anime.synopsis = syn
            }
            if !dto.title.isEmpty {
                anime.title = dto.title
            }
            if let en = dto.titleEnglish, !en.isEmpty {
                anime.englishTitle = en
            }
            if let jp = dto.titleJapanese, !jp.isEmpty {
                anime.japaneseTitle = jp
            }
            if let release = dto.startDateFormatted, !release.isEmpty {
                anime.seasonYear = release
            }
            if let endDate = dto.airingEndDateFormatted, !endDate.isEmpty {
                anime.airingEndDate = endDate
            }
            if let genres = dto.genres, !genres.isEmpty {
                anime.genres = genres.map { $0.name }
            }
            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID, forceRefresh: true)
            if !dubs.isEmpty {
                anime.dubbedLanguages = dubs.map { $0.name }
            }
            try? context.save()
        }
    }

    public static func stripHTMLTags(from string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        let cleaned = string
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard let url = URL(string: "https://graphql.anilist.co") else { return [:] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-Desktop/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["ids": malIDs]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [:] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let pageObj = dataObj["Page"] as? [String: Any],
                  let mediaList = pageObj["media"] as? [[String: Any]] else {
                return [:]
            }

            var map: [Int: FetchedMetadata] = [:]

            for item in mediaList {
                guard let idMal = item["idMal"] as? Int else { continue }

                let coverObj = item["coverImage"] as? [String: Any]
                let coverLarge = coverObj?["large"] as? String ?? coverObj?["extraLarge"] as? String

                let titleObj = item["title"] as? [String: Any]
                let native = titleObj?["native"] as? String
                let romaji = titleObj?["romaji"] as? String
                let english = titleObj?["english"] as? String
                let synonyms = item["synonyms"] as? [String] ?? []

                var resolvedEnglish = english
                if resolvedEnglish == nil || resolvedEnglish?.isEmpty == true {
                    for syn in synonyms {
                        let trimmed = syn.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.canBeConverted(to: .ascii) && trimmed.count >= 2 {
                            resolvedEnglish = trimmed
                            break
                        }
                    }
                }

                let desc = Self.stripHTMLTags(from: item["description"] as? String)

                let avgScore = (item["averageScore"] as? Double ?? Double(item["averageScore"] as? Int ?? 0)) / 10.0
                let rawStatus = item["status"] as? String
                let eps = item["episodes"] as? Int

                // Parse exact start and end dates
                let startObj = item["startDate"] as? [String: Any]
                let startYear = startObj?["year"] as? Int
                let startMonth = startObj?["month"] as? Int
                let startDay = startObj?["day"] as? Int

                let formattedDate = AnimeDateFormatter.format(year: startYear, month: startMonth, day: startDay)

                let endObj = item["endDate"] as? [String: Any]
                let endYear = endObj?["year"] as? Int
                let endMonth = endObj?["month"] as? Int
                let endDay = endObj?["day"] as? Int

                let formattedEndDate = AnimeDateFormatter.format(year: endYear, month: endMonth, day: endDay)

                let season = item["season"] as? String
                let year = item["seasonYear"] as? Int
                var fallbackDate: String? = nil
                if let s = season?.capitalized, let y = year {
                    fallbackDate = "\(s) \(y)"
                } else if let y = year {
                    fallbackDate = "\(y)"
                }

                let finalReleaseDate = formattedDate ?? fallbackDate

                let genres = item["genres"] as? [String] ?? []

                let meta = FetchedMetadata(
                    malID: idMal,
                    title: romaji,
                    englishTitle: resolvedEnglish,
                    japaneseTitle: native,
                    coverURL: coverLarge,
                    synopsis: desc,
                    score: avgScore > 0 ? avgScore : nil,
                    airingStatusRaw: rawStatus,
                    seasonYear: finalReleaseDate,
                    airingEndDate: formattedEndDate,
                    episodes: eps,
                    genres: genres
                )
                map[idMal] = meta
            }

            return map
        } catch {
            return [:]
        }
    }
}
