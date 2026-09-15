import Foundation
import Observation

@Observable
@MainActor
public final class AnimeRelationsService {
    public static let shared = AnimeRelationsService()

    private var cache: [Int: [RelatedAnimeItem]] = [:]
    private var activeTasks: [Int: Task<[RelatedAnimeItem], Never>] = [:]

    private var franchiseCache: [Int: [RelatedAnimeItem]] = [:]
    private var activeFranchiseTasks: [Int: Task<[RelatedAnimeItem], Never>] = [:]

    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Chibiori/relations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let franchiseDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Chibiori/franchises", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    /// Fetches all media entries belonging to the anime franchise (all seasons, movies, OVAs, spin-offs).
    /// Leverages AniList franchise search, direct relations, local library matching, and disk caching.
    public func fetchFullFranchise(
        malID: Int,
        title: String,
        englishTitle: String? = nil,
        allLibrary: [TrackedAnime] = [],
        forceRefresh: Bool = false
    ) async -> [RelatedAnimeItem] {
        guard malID != 0 || !title.isEmpty else { return [] }

        // 1. In-memory cache
        if !forceRefresh, let cached = franchiseCache[malID], !cached.isEmpty {
            return cached
        }

        // 2. Persistent disk cache
        if !forceRefresh, let diskItems = loadFranchiseFromDisk(for: malID), !diskItems.isEmpty {
            franchiseCache[malID] = diskItems
            return diskItems
        }

        // 3. Deduplicate in-flight network requests
        if let existingTask = activeFranchiseTasks[malID] {
            return await existingTask.value
        }

        let task = Task<[RelatedAnimeItem], Never> { @MainActor in
            // A. Fetch direct relations first (to know exact PREQUEL/SEQUEL links)
            let directRelations = await self.fetchRelations(for: malID, title: title, forceRefresh: forceRefresh)
            var directRelMap: [Int: String] = [:]
            for rel in directRelations {
                directRelMap[rel.malID] = rel.relationType
            }

            // B. Prepare search root
            let cleanTitle = self.cleanFranchiseRoot(title)
            let cleanEnTitle = englishTitle.map { self.cleanFranchiseRoot($0) }
            let searchQuery = cleanTitle.count >= 3 ? cleanTitle : (cleanEnTitle ?? title)

            // C. Query AniList franchise media
            var rawMedia = await self.performAniListFranchiseQuery(query: searchQuery, originalMalID: malID)
            if rawMedia.isEmpty, let cleanEn = cleanEnTitle, cleanEn.count >= 3, cleanEn != cleanTitle {
                rawMedia = await self.performAniListFranchiseQuery(query: cleanEn, originalMalID: malID)
            }

            // D. Merge direct relations and AniList franchise items
            var items: [RelatedAnimeItem] = []
            var seenIDs = Set<Int>()

            for item in rawMedia {
                seenIDs.insert(item.malID)
                if item.malID == malID {
                    items.append(item.copy(withRelationType: "CURRENT"))
                } else if let directType = directRelMap[item.malID], directType == "PREQUEL" || directType == "SEQUEL" {
                    items.append(item.copy(withRelationType: directType))
                } else {
                    items.append(item)
                }
            }

            // E. Ensure direct relations are not missed
            for direct in directRelations where !seenIDs.contains(direct.malID) {
                seenIDs.insert(direct.malID)
                items.append(direct)
            }

            // F. Ensure current anime itself is present
            if !seenIDs.contains(malID), malID != 0 {
                seenIDs.insert(malID)
                let currentItem = RelatedAnimeItem(
                    malID: malID,
                    relationType: "CURRENT",
                    title: title,
                    englishTitle: englishTitle,
                    format: "TV"
                )
                items.append(currentItem)
            }

            // G. Cross-discover from local library if available
            for libraryAnime in allLibrary where !seenIDs.contains(libraryAnime.malID) {
                let cleanLib = self.cleanFranchiseRoot(libraryAnime.title)
                let cleanLibEn = self.cleanFranchiseRoot(libraryAnime.englishTitle ?? "")
                let matches = (!cleanLib.isEmpty && (cleanLib == cleanTitle || cleanLib.contains(cleanTitle) || cleanTitle.contains(cleanLib))) ||
                              (!cleanLibEn.isEmpty && cleanEnTitle != nil && (cleanLibEn == cleanEnTitle! || cleanLibEn.contains(cleanEnTitle!) || cleanEnTitle!.contains(cleanLibEn)))

                if matches {
                    seenIDs.insert(libraryAnime.malID)
                    let libItem = RelatedAnimeItem(
                        malID: libraryAnime.malID,
                        relationType: libraryAnime.malID == malID ? "CURRENT" : (directRelMap[libraryAnime.malID] ?? "MAIN_STORY"),
                        title: libraryAnime.title,
                        englishTitle: libraryAnime.englishTitle,
                        japaneseTitle: libraryAnime.japaneseTitle,
                        coverImageURL: libraryAnime.coverImageRemoteURL,
                        format: "TV",
                        status: libraryAnime.airingStatusRaw,
                        episodes: libraryAnime.totalEpisodes,
                        seasonYear: self.extractYear(from: libraryAnime),
                        synopsis: libraryAnime.synopsis
                    )
                    items.append(libItem)
                }
            }

            // H. Sort chronologically by year, then priority, then title
            items.sort { a, b in
                let yA = a.seasonYear ?? 9999
                let yB = b.seasonYear ?? 9999
                if yA != yB {
                    return yA < yB
                }
                if a.priorityRank != b.priorityRank {
                    return a.priorityRank < b.priorityRank
                }
                return a.title < b.title
            }

            if !items.isEmpty {
                self.franchiseCache[malID] = items
                self.saveFranchiseToDisk(items, for: malID)
            } else if let diskItems = self.loadFranchiseFromDisk(for: malID), !diskItems.isEmpty {
                items = diskItems
                self.franchiseCache[malID] = diskItems
            }

            self.activeFranchiseTasks.removeValue(forKey: malID)
            return items
        }

        activeFranchiseTasks[malID] = task
        return await task.value
    }

    /// Fetches all related anime seasons (prequels, sequels, parent story, side stories) for the given MAL ID.
    /// Supports title fallback, AniList GraphQL, disk caching, retry on rate limits, and Jikan fallback.
    public func fetchRelations(for malID: Int, title: String? = nil, forceRefresh: Bool = false) async -> [RelatedAnimeItem] {
        guard malID > 0 || (title != nil && !title!.isEmpty) else { return [] }

        // 1. In-memory cache (only use if non-empty, unless forceRefresh is true)
        if !forceRefresh, let cached = cache[malID], !cached.isEmpty {
            return cached
        }

        // 2. Persistent disk cache
        if !forceRefresh, let diskItems = loadFromDisk(for: malID), !diskItems.isEmpty {
            cache[malID] = diskItems
            return diskItems
        }

        // 3. Deduplicate in-flight network requests
        if let existingTask = activeTasks[malID] {
            return await existingTask.value
        }

        let task = Task<[RelatedAnimeItem], Never> { @MainActor in
            var results: [RelatedAnimeItem] = []

            // Primary: Query AniList GraphQL by MAL ID (or AniList ID if negative)
            if malID != 0 {
                results = await self.performAniListRelationsQuery(for: malID)
            }

            // Secondary: If empty and title is available, query AniList by search title
            if results.isEmpty, let title, !title.isEmpty {
                results = await self.performAniListTitleRelationsQuery(title: title, originalMalID: malID)
            }

            // Tertiary: Fallback to Jikan REST API if still empty and valid positive MAL ID
            if results.isEmpty && malID > 0 {
                results = await self.performJikanRelationsQuery(for: malID)
            }

            if !results.isEmpty {
                self.cache[malID] = results
                self.saveToDisk(results, for: malID)
            } else if let diskItems = self.loadFromDisk(for: malID), !diskItems.isEmpty {
                // If network failed (e.g. rate limit), preserve previous disk cache
                results = diskItems
                self.cache[malID] = diskItems
            }

            self.activeTasks.removeValue(forKey: malID)
            return results
        }

        activeTasks[malID] = task
        return await task.value
    }

    // MARK: - AniList GraphQL by MAL ID (or AniList ID if negative)
    private func performAniListRelationsQuery(for malID: Int, retryCount: Int = 1) async -> [RelatedAnimeItem] {
        let isAniListId = malID < 0
        let targetId = isAniListId ? -malID : malID
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

        guard let url = URL(string: "https://graphql.anilist.co") else { return [] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["id": targetId]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }

            if http.statusCode == 429 && retryCount > 0 {
                // Rate limited - wait 600ms and retry once
                try? await Task.sleep(nanoseconds: 600_000_000)
                return await performAniListRelationsQuery(for: malID, retryCount: retryCount - 1)
            }

            guard http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let media = dataObj["Media"] as? [String: Any],
                  let relObj = media["relations"] as? [String: Any],
                  let edges = relObj["edges"] as? [[String: Any]] else {
                return []
            }

            return parseRelationsEdges(edges, originalMalID: malID)
        } catch {
            return []
        }
    }

    // MARK: - AniList GraphQL by Title Search
    private func performAniListTitleRelationsQuery(title: String, originalMalID: Int, retryCount: Int = 1) async -> [RelatedAnimeItem] {
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

        guard let url = URL(string: "https://graphql.anilist.co") else { return [] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["search": title]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }

            if http.statusCode == 429 && retryCount > 0 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                return await performAniListTitleRelationsQuery(title: title, originalMalID: originalMalID, retryCount: retryCount - 1)
            }

            guard http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let media = dataObj["Media"] as? [String: Any],
                  let relObj = media["relations"] as? [String: Any],
                  let edges = relObj["edges"] as? [[String: Any]] else {
                return []
            }

            return parseRelationsEdges(edges, originalMalID: originalMalID)
        } catch {
            return []
        }
    }

    // MARK: - Jikan REST API Fallback
    private func performJikanRelationsQuery(for malID: Int) async -> [RelatedAnimeItem] {
        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(malID)/relations") else { return [] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else { return [] }

            var items: [RelatedAnimeItem] = []
            for block in dataArray {
                guard let relName = block["relation"] as? String,
                      let entries = block["entry"] as? [[String: Any]] else { continue }
                let relType = relName.uppercased().replacingOccurrences(of: " ", with: "_")
                for entry in entries {
                    guard let type = entry["type"] as? String, type.lowercased() == "anime",
                          let relMalId = entry["mal_id"] as? Int, relMalId > 0, relMalId != malID,
                          let name = entry["name"] as? String else { continue }
                    items.append(RelatedAnimeItem(malID: relMalId, relationType: relType, title: name))
                }
            }
            return items
        } catch {
            return []
        }
    }

    // MARK: - Edge Parser
    private func parseRelationsEdges(_ edges: [[String: Any]], originalMalID: Int) -> [RelatedAnimeItem] {
        var items: [RelatedAnimeItem] = []
        var seenIDs = Set<Int>()

        for edge in edges {
            let relType = (edge["relationType"] as? String ?? "").uppercased()
            guard let node = edge["node"] as? [String: Any] else { continue }

            // Only include anime relations (discard manga, light novels, etc.)
            let mediaType = (node["type"] as? String ?? "").uppercased()
            guard mediaType == "ANIME" else { continue }

            // Discard manga/novel formats just in case
            let format = (node["format"] as? String ?? "").uppercased()
            if format == "MANGA" || format == "NOVEL" || format == "ONE_SHOT" {
                continue
            }

            // If idMal is missing on AniList, fallback to negative AniList ID so it isn't lost
            let idMal = node["idMal"] as? Int
            let aniId = node["id"] as? Int ?? 0
            let effectiveID = (idMal != nil && idMal! > 0) ? idMal! : (aniId > 0 ? -aniId : 0)

            guard effectiveID != 0, effectiveID != originalMalID else {
                continue
            }

            if seenIDs.contains(effectiveID) {
                continue
            }
            seenIDs.insert(effectiveID)

            let titleObj = node["title"] as? [String: Any]
            let romaji = (titleObj?["romaji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let english = (titleObj?["english"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let native = (titleObj?["native"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let finalTitle = !romaji.isEmpty ? romaji : (english ?? "Untitled")

            let coverImageObj = node["coverImage"] as? [String: Any]
            let coverUrl = coverImageObj?["large"] as? String

            let status = node["status"] as? String
            let episodes = node["episodes"] as? Int
            let season = node["season"] as? String
            let seasonYear = node["seasonYear"] as? Int
            let rawDesc = node["description"] as? String
            let synopsis = MetadataHydrationService.stripHTMLTags(from: rawDesc)

            let item = RelatedAnimeItem(
                malID: effectiveID,
                relationType: relType,
                title: finalTitle,
                englishTitle: english,
                japaneseTitle: native,
                coverImageURL: coverUrl,
                format: format.isEmpty ? nil : format,
                status: status,
                episodes: episodes,
                season: season,
                seasonYear: seasonYear,
                synopsis: synopsis
            )
            items.append(item)
        }

        // Sort: Prequels & Sequels first, then by seasonYear/title
        items.sort { a, b in
            if a.priorityRank != b.priorityRank {
                return a.priorityRank < b.priorityRank
            }
            if let yA = a.seasonYear, let yB = b.seasonYear, yA != yB {
                return yA < yB
            }
            return a.title < b.title
        }

        return items
    }

    // MARK: - AniList GraphQL Franchise Query
    private func performAniListFranchiseQuery(query: String, originalMalID: Int, retryCount: Int = 1) async -> [RelatedAnimeItem] {
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
              startDate {
                year
                month
                day
              }
              description
              coverImage {
                large
              }
              title {
                romaji
                english
                native
              }
            }
          }
        }
        """

        guard let url = URL(string: "https://graphql.anilist.co") else { return [] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["search": query]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }

            if http.statusCode == 429 && retryCount > 0 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                return await performAniListFranchiseQuery(query: query, originalMalID: originalMalID, retryCount: retryCount - 1)
            }

            guard http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let page = dataObj["Page"] as? [String: Any],
                  let mediaList = page["media"] as? [[String: Any]] else {
                return []
            }

            return parseFranchiseMedia(mediaList, originalMalID: originalMalID)
        } catch {
            return []
        }
    }

    private func parseFranchiseMedia(_ mediaList: [[String: Any]], originalMalID: Int) -> [RelatedAnimeItem] {
        var items: [RelatedAnimeItem] = []
        var seenIDs = Set<Int>()

        for node in mediaList {
            let mediaType = (node["type"] as? String ?? "").uppercased()
            guard mediaType == "ANIME" else { continue }

            let format = (node["format"] as? String ?? "").uppercased()
            if format == "MANGA" || format == "NOVEL" || format == "ONE_SHOT" {
                continue
            }

            let idMal = node["idMal"] as? Int
            let aniId = node["id"] as? Int ?? 0
            let effectiveID = (idMal != nil && idMal! > 0) ? idMal! : (aniId > 0 ? -aniId : 0)

            guard effectiveID != 0 else { continue }
            if seenIDs.contains(effectiveID) { continue }
            seenIDs.insert(effectiveID)

            let titleObj = node["title"] as? [String: Any]
            let romaji = (titleObj?["romaji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let english = (titleObj?["english"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let native = (titleObj?["native"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = !romaji.isEmpty ? romaji : (english ?? "Untitled")

            let coverImageObj = node["coverImage"] as? [String: Any]
            let coverUrl = coverImageObj?["large"] as? String

            let status = node["status"] as? String
            let episodes = node["episodes"] as? Int
            let season = node["season"] as? String
            var seasonYear = node["seasonYear"] as? Int

            if seasonYear == nil, let startDate = node["startDate"] as? [String: Any], let sYear = startDate["year"] as? Int {
                seasonYear = sYear
            }

            let rawDesc = node["description"] as? String
            let synopsis = MetadataHydrationService.stripHTMLTags(from: rawDesc)

            let relType: String
            if effectiveID == originalMalID {
                relType = "CURRENT"
            } else {
                switch format {
                case "MOVIE":
                    relType = "MOVIE"
                case "OVA", "SPECIAL":
                    relType = "OVA"
                case "ONA":
                    relType = "ONA"
                case "TV", "TV_SHORT":
                    let lower = (romaji + " " + (english ?? "")).lowercased()
                    if lower.contains("spin-off") || lower.contains("spinoff") || lower.contains("nikki") || lower.contains("diaries") {
                        relType = "SPIN_OFF"
                    } else {
                        relType = "MAIN_STORY"
                    }
                default:
                    relType = "ALTERNATIVE"
                }
            }

            let item = RelatedAnimeItem(
                malID: effectiveID,
                relationType: relType,
                title: finalTitle,
                englishTitle: english,
                japaneseTitle: native,
                coverImageURL: coverUrl,
                format: format.isEmpty ? nil : format,
                status: status,
                episodes: episodes,
                season: season,
                seasonYear: seasonYear,
                synopsis: synopsis
            )
            items.append(item)
        }

        return items
    }

    // MARK: - Local Franchise Cross-Discovery (Offline Fallback)
    /// Discovers related seasons from the user's existing library by matching franchise root title
    public func discoverLibraryFranchiseRelations(for anime: TrackedAnime, allLibrary: [TrackedAnime]) -> [RelatedAnimeItem] {
        let cleanCurrent = cleanFranchiseRoot(anime.title)
        guard cleanCurrent.count >= 4 else { return [] }

        var items: [RelatedAnimeItem] = []
        for other in allLibrary where other.malID != anime.malID {
            let cleanOther = cleanFranchiseRoot(other.title)
            let cleanOtherEn = cleanFranchiseRoot(other.englishTitle ?? "")

            let matches = (cleanOther == cleanCurrent) ||
                          (cleanOther.contains(cleanCurrent) && cleanCurrent.count >= 6) ||
                          (cleanCurrent.contains(cleanOther) && cleanOther.count >= 6) ||
                          (!cleanOtherEn.isEmpty && cleanOtherEn == cleanFranchiseRoot(anime.englishTitle ?? ""))

            if matches {
                let relType = deduceRelationType(current: anime, other: other)
                let item = RelatedAnimeItem(
                    malID: other.malID,
                    relationType: relType,
                    title: other.title,
                    englishTitle: other.englishTitle,
                    japaneseTitle: other.japaneseTitle,
                    coverImageURL: other.coverImageRemoteURL,
                    format: "TV",
                    status: other.airingStatusRaw,
                    episodes: other.totalEpisodes,
                    seasonYear: extractYear(from: other),
                    synopsis: other.synopsis
                )
                items.append(item)
            }
        }

        return items
    }

    private func extractYear(from anime: TrackedAnime) -> Int? {
        guard let s = anime.seasonYear else { return nil }
        if let match = s.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            return Int(s[match])
        }
        return nil
    }

    public func cleanFranchiseRoot(_ raw: String) -> String {
        var str = raw.lowercased()
        let patterns = [
            "\\d+(st|nd|rd|th)\\s+season",
            "season\\s+\\d+",
            "part\\s+\\d+",
            "cour\\s+\\d+",
            "the\\s+movie.*",
            "[:!?,.-]+"
        ]
        for pat in patterns {
            str = str.replacingOccurrences(of: pat, with: " ", options: .regularExpression)
        }
        return str.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deduceRelationType(current: TrackedAnime, other: TrackedAnime) -> String {
        let currentSeason = extractSeasonNumber(current.title) ?? extractSeasonNumber(current.englishTitle ?? "")
        let otherSeason = extractSeasonNumber(other.title) ?? extractSeasonNumber(other.englishTitle ?? "")

        if let c = currentSeason, let o = otherSeason {
            if o < c { return "PREQUEL" }
            if o > c { return "SEQUEL" }

            // If same season number, check part / cour number (e.g. Season 2 vs Season 2 Part 2)
            let cPart = extractPartNumber(current.title) ?? extractPartNumber(current.englishTitle ?? "")
            let oPart = extractPartNumber(other.title) ?? extractPartNumber(other.englishTitle ?? "")
            if let cp = cPart, let op = oPart, cp != op {
                return op < cp ? "PREQUEL" : "SEQUEL"
            } else if cPart == nil, let op = oPart, op > 1 {
                return "SEQUEL"
            } else if let cp = cPart, cp > 1, oPart == nil {
                return "PREQUEL"
            }
        } else if let c = currentSeason, c >= 1, otherSeason == nil {
            return "PREQUEL"
        } else if currentSeason == nil, let o = otherSeason, o >= 1 {
            return "SEQUEL"
        }

        if let yC = extractYear(from: current), let yO = extractYear(from: other), yC != yO {
            return yO < yC ? "PREQUEL" : "SEQUEL"
        }

        return "ALTERNATIVE"
    }

    private func extractPartNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        if let match = lower.range(of: "(part|cour)\\s*(\\d+)", options: .regularExpression) {
            let sub = String(lower[match])
            let nums = sub.compactMap { Int(String($0)) }
            return nums.first
        }
        return nil
    }

    private func extractSeasonNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        if let match = lower.range(of: "(season|part|cour)\\s*(\\d+)", options: .regularExpression) {
            let sub = String(lower[match])
            let nums = sub.compactMap { Int(String($0)) }
            return nums.first
        }
        if let match = lower.range(of: "(\\d+)(st|nd|rd|th)\\s*season", options: .regularExpression) {
            let sub = String(lower[match])
            let nums = sub.compactMap { Int(String($0)) }
            return nums.first
        }
        return nil
    }

    // MARK: - Relations Disk Persistence
    private func loadFromDisk(for malID: Int) -> [RelatedAnimeItem]? {
        let fileURL = cacheDirectory.appendingPathComponent("\(malID).json")
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([RelatedAnimeItem].self, from: data) else {
            return nil
        }
        return items
    }

    private func saveToDisk(_ items: [RelatedAnimeItem], for malID: Int) {
        guard !items.isEmpty else { return }
        let fileURL = cacheDirectory.appendingPathComponent("\(malID).json")
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - Franchise Disk Persistence
    private func loadFranchiseFromDisk(for malID: Int) -> [RelatedAnimeItem]? {
        let fileURL = franchiseDirectory.appendingPathComponent("\(malID).json")
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([RelatedAnimeItem].self, from: data) else {
            return nil
        }
        return items
    }

    private func saveFranchiseToDisk(_ items: [RelatedAnimeItem], for malID: Int) {
        guard !items.isEmpty else { return }
        let fileURL = franchiseDirectory.appendingPathComponent("\(malID).json")
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    /// Preloads or injects relations into cache (useful for testing or previews)
    public func setCachedRelations(_ relations: [RelatedAnimeItem], for malID: Int) {
        cache[malID] = relations
        saveToDisk(relations, for: malID)
    }

    /// Preloads or injects franchise into cache (useful for testing or previews)
    public func setCachedFranchise(_ franchise: [RelatedAnimeItem], for malID: Int) {
        franchiseCache[malID] = franchise
        saveFranchiseToDisk(franchise, for: malID)
    }

    /// Clears the in-memory cache
    public func clearCache() {
        cache.removeAll()
        franchiseCache.removeAll()
    }
}
