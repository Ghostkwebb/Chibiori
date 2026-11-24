import Foundation

/// Sendable snapshot of a `TrackedAnime` entry used for thread-safe offline franchise discovery.
public struct LibraryMatchSnapshot: Sendable, Hashable {
    public let malID: Int
    public let title: String
    public let englishTitle: String?
    public let japaneseTitle: String?
    public let coverImageRemoteURL: String
    public let airingStatusRaw: String
    public let totalEpisodes: Int?
    public let seasonYear: String?
    public let synopsis: String

    public init(
        malID: Int,
        title: String,
        englishTitle: String? = nil,
        japaneseTitle: String? = nil,
        coverImageRemoteURL: String = "",
        airingStatusRaw: String = "",
        totalEpisodes: Int? = nil,
        seasonYear: String? = nil,
        synopsis: String = ""
    ) {
        self.malID = malID
        self.title = title
        self.englishTitle = englishTitle
        self.japaneseTitle = japaneseTitle
        self.coverImageRemoteURL = coverImageRemoteURL
        self.airingStatusRaw = airingStatusRaw
        self.totalEpisodes = totalEpisodes
        self.seasonYear = seasonYear
        self.synopsis = synopsis
    }
}

extension TrackedAnime {
    /// Creates a `Sendable` snapshot for off-main-actor relation and franchise matching.
    public var matchSnapshot: LibraryMatchSnapshot {
        LibraryMatchSnapshot(
            malID: malID,
            title: title,
            englishTitle: englishTitle,
            japaneseTitle: japaneseTitle,
            coverImageRemoteURL: coverImageRemoteURL,
            airingStatusRaw: airingStatusRaw,
            totalEpisodes: totalEpisodes,
            seasonYear: seasonYear,
            synopsis: synopsis
        )
    }
}

private struct DiskCacheEnvelope: Codable {
    let cachedAt: Date
    let items: [RelatedAnimeItem]
}

/// Actor managing anime relations, full franchise graphs, disk TTL caching, and local cross-discovery.
public actor AnimeRelationsService {
    public static let shared = AnimeRelationsService()

    private static let cacheTTL: TimeInterval = 7 * 24 * 3600 // 7 days
    private static let maxMemoryEntries = 120

    private var cache: [Int: [RelatedAnimeItem]] = [:]
    private var cacheOrder: [Int] = []
    private var activeTasks: [Int: Task<[RelatedAnimeItem], Never>] = [:]

    private var franchiseCache: [Int: [RelatedAnimeItem]] = [:]
    private var franchiseCacheOrder: [Int] = []
    private var activeFranchiseTasks: [Int: Task<[RelatedAnimeItem], Never>] = [:]

    private let cacheDirectory: URL
    private let franchiseDirectory: URL
    private let aniList: AniListClient
    private let session: URLSession

    public init(
        cacheRootURL: URL? = nil,
        aniList: AniListClient = .shared,
        session: URLSession = .shared
    ) {
        let baseRoot: URL
        if let cacheRootURL {
            baseRoot = cacheRootURL
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            baseRoot = paths[0].appendingPathComponent("Chibiori", isDirectory: true)
        }

        let relDir = baseRoot.appendingPathComponent("relations", isDirectory: true)
        let franDir = baseRoot.appendingPathComponent("franchises", isDirectory: true)
        try? FileManager.default.createDirectory(at: relDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: franDir, withIntermediateDirectories: true)

        self.cacheDirectory = relDir
        self.franchiseDirectory = franDir
        self.aniList = aniList
        self.session = session
    }

    // MARK: - Full Franchise Graph

    public func fetchFullFranchise(
        malID: Int,
        title: String,
        englishTitle: String? = nil,
        allLibrary: [LibraryMatchSnapshot] = [],
        forceRefresh: Bool = false
    ) async -> [RelatedAnimeItem] {
        guard malID != 0 || !title.isEmpty else { return [] }

        if !forceRefresh, let cached = franchiseCache[malID], !cached.isEmpty {
            return cached
        }

        if !forceRefresh, let diskItems = loadDiskItems(from: franchiseDirectory, for: malID), !diskItems.isEmpty {
            storeFranchiseInMemory(diskItems, for: malID)
            return diskItems
        }

        if let existingTask = activeFranchiseTasks[malID] {
            return await existingTask.value
        }

        let task = Task<[RelatedAnimeItem], Never> {
            let directRelations = await self.fetchRelations(for: malID, title: title, forceRefresh: forceRefresh)
            var directRelMap: [Int: String] = [:]
            for rel in directRelations {
                directRelMap[rel.malID] = rel.relationType
            }

            let cleanTitle = self.cleanFranchiseRoot(title)
            let cleanEnTitle = englishTitle.map { self.cleanFranchiseRoot($0) }
            let searchQuery = cleanTitle.count >= 3 ? cleanTitle : (cleanEnTitle ?? title)

            var rawNodes = await self.aniList.fetchFranchiseMedia(query: searchQuery)
            if rawNodes.isEmpty, let cleanEn = cleanEnTitle, cleanEn.count >= 3, cleanEn != cleanTitle {
                rawNodes = await self.aniList.fetchFranchiseMedia(query: cleanEn)
            }

            var seenRawIDs = Set<Int>()
            let rawMedia: [RelatedAnimeItem] = rawNodes.compactMap { node in
                guard let base = node.toFranchiseRelatedItem() else { return nil }
                guard !seenRawIDs.contains(base.malID) else { return nil }
                seenRawIDs.insert(base.malID)
                let inferredType = Self.inferFranchiseRelationType(item: base, originalMalID: malID)
                return base.copy(withRelationType: inferredType)
            }

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

            for direct in directRelations where !seenIDs.contains(direct.malID) {
                seenIDs.insert(direct.malID)
                items.append(direct)
            }

            if !seenIDs.contains(malID), malID != 0 {
                seenIDs.insert(malID)
                items.append(
                    RelatedAnimeItem(
                        malID: malID,
                        relationType: "CURRENT",
                        title: title,
                        englishTitle: englishTitle,
                        format: "TV"
                    )
                )
            }

            for libraryAnime in allLibrary where !seenIDs.contains(libraryAnime.malID) {
                let cleanLib = self.cleanFranchiseRoot(libraryAnime.title)
                let cleanLibEn = self.cleanFranchiseRoot(libraryAnime.englishTitle ?? "")
                let matches = (!cleanLib.isEmpty && (cleanLib == cleanTitle || cleanLib.contains(cleanTitle) || cleanTitle.contains(cleanLib)))
                    || (!cleanLibEn.isEmpty && cleanEnTitle != nil && (cleanLibEn == cleanEnTitle! || cleanLibEn.contains(cleanEnTitle!) || cleanEnTitle!.contains(cleanLibEn)))

                if matches {
                    seenIDs.insert(libraryAnime.malID)
                    items.append(
                        RelatedAnimeItem(
                            malID: libraryAnime.malID,
                            relationType: libraryAnime.malID == malID ? "CURRENT" : (directRelMap[libraryAnime.malID] ?? "MAIN_STORY"),
                            title: libraryAnime.title,
                            englishTitle: libraryAnime.englishTitle,
                            japaneseTitle: libraryAnime.japaneseTitle,
                            coverImageURL: libraryAnime.coverImageRemoteURL,
                            format: "TV",
                            status: libraryAnime.airingStatusRaw,
                            episodes: libraryAnime.totalEpisodes,
                            seasonYear: Self.extractYear(from: libraryAnime),
                            synopsis: libraryAnime.synopsis
                        )
                    )
                }
            }

            items.sort { a, b in
                let yA = a.seasonYear ?? 9999
                let yB = b.seasonYear ?? 9999
                if yA != yB { return yA < yB }
                if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
                return a.title < b.title
            }

            return items
        }

        activeFranchiseTasks[malID] = task
        var items = await task.value
        activeFranchiseTasks.removeValue(forKey: malID)

        if !items.isEmpty {
            storeFranchiseInMemory(items, for: malID)
            saveDiskItems(items, to: franchiseDirectory, for: malID)
        } else if let staleDisk = loadDiskItems(from: franchiseDirectory, for: malID, ignoreExpiration: true), !staleDisk.isEmpty {
            items = staleDisk
            storeFranchiseInMemory(staleDisk, for: malID)
        }

        return items
    }

    // MARK: - Direct Relations

    public func fetchRelations(for malID: Int, title: String? = nil, forceRefresh: Bool = false) async -> [RelatedAnimeItem] {
        guard malID != 0 || (title != nil && !title!.isEmpty) else { return [] }

        if !forceRefresh, let cached = cache[malID], !cached.isEmpty {
            return cached
        }

        if !forceRefresh, let diskItems = loadDiskItems(from: cacheDirectory, for: malID), !diskItems.isEmpty {
            storeRelationsInMemory(diskItems, for: malID)
            return diskItems
        }

        if let existingTask = activeTasks[malID] {
            return await existingTask.value
        }

        let task = Task<[RelatedAnimeItem], Never> {
            var results: [RelatedAnimeItem] = []

            if malID != 0 {
                let edges = await self.aniList.fetchRelations(malId: malID)
                results = Self.parseRelationsEdges(edges, originalMalID: malID)
            }

            if results.isEmpty, let title, !title.isEmpty {
                let edges = await self.aniList.fetchRelationsByTitle(title)
                results = Self.parseRelationsEdges(edges, originalMalID: malID)
            }

            if results.isEmpty, malID > 0 {
                results = await self.performJikanRelationsQuery(for: malID)
            }

            return results
        }

        activeTasks[malID] = task
        var results = await task.value
        activeTasks.removeValue(forKey: malID)

        if !results.isEmpty {
            storeRelationsInMemory(results, for: malID)
            saveDiskItems(results, to: cacheDirectory, for: malID)
        } else if let staleDisk = loadDiskItems(from: cacheDirectory, for: malID, ignoreExpiration: true), !staleDisk.isEmpty {
            results = staleDisk
            storeRelationsInMemory(staleDisk, for: malID)
        }

        return results
    }

    // MARK: - Jikan REST Fallback

    private func performJikanRelationsQuery(for malID: Int) async -> [RelatedAnimeItem] {
        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(malID)/relations") else { return [] }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
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

    // MARK: - Parsing Helpers

    private nonisolated static func parseRelationsEdges(_ edges: [AniListRelationEdgeDTO], originalMalID: Int) -> [RelatedAnimeItem] {
        var items: [RelatedAnimeItem] = []
        var seenIDs = Set<Int>()

        for edge in edges {
            let relType = (edge.relationType ?? "").uppercased()
            guard let node = edge.node else { continue }

            let mediaType = (node.type ?? "").uppercased()
            guard mediaType == "ANIME" else { continue }

            let format = (node.format ?? "").uppercased()
            if format == "MANGA" || format == "NOVEL" || format == "ONE_SHOT" {
                continue
            }

            let effectiveID: Int
            if let idMal = node.idMal, idMal > 0 {
                effectiveID = idMal
            } else if let aniId = node.id, aniId > 0 {
                effectiveID = -aniId
            } else {
                continue
            }

            guard effectiveID != originalMalID, !seenIDs.contains(effectiveID) else { continue }
            seenIDs.insert(effectiveID)

            let romaji = node.title?.romaji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let english = node.title?.english?.trimmingCharacters(in: .whitespacesAndNewlines)
            let native = node.title?.native?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = !romaji.isEmpty ? romaji : (english ?? "Untitled")

            items.append(
                RelatedAnimeItem(
                    malID: effectiveID,
                    relationType: relType,
                    title: finalTitle,
                    englishTitle: english,
                    japaneseTitle: native,
                    coverImageURL: node.coverImage?.large ?? node.coverImage?.extraLarge,
                    format: format.isEmpty ? nil : format,
                    status: node.status,
                    episodes: node.episodes,
                    season: node.season,
                    seasonYear: node.seasonYear ?? node.startDate?.year,
                    synopsis: HTMLCleaner.strip(from: node.description)
                )
            )
        }

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

    private nonisolated static func inferFranchiseRelationType(item: RelatedAnimeItem, originalMalID: Int) -> String {
        if item.malID == originalMalID { return "CURRENT" }
        let format = (item.format ?? "").uppercased()
        switch format {
        case "MOVIE": return "MOVIE"
        case "OVA", "SPECIAL": return "OVA"
        case "ONA": return "ONA"
        case "TV", "TV_SHORT":
            let lower = (item.title + " " + (item.englishTitle ?? "")).lowercased()
            if lower.contains("spin-off") || lower.contains("spinoff") || lower.contains("nikki") || lower.contains("diaries") {
                return "SPIN_OFF"
            }
            return "MAIN_STORY"
        default:
            return "ALTERNATIVE"
        }
    }

    // MARK: - Local Franchise Cross-Discovery (Offline Fallback)

    public nonisolated func discoverLibraryFranchiseRelations(
        for anime: LibraryMatchSnapshot,
        allLibrary: [LibraryMatchSnapshot]
    ) -> [RelatedAnimeItem] {
        let cleanCurrent = cleanFranchiseRoot(anime.title)
        guard cleanCurrent.count >= 4 else { return [] }

        var items: [RelatedAnimeItem] = []
        for other in allLibrary where other.malID != anime.malID {
            let cleanOther = cleanFranchiseRoot(other.title)
            let cleanOtherEn = cleanFranchiseRoot(other.englishTitle ?? "")

            let matches = (cleanOther == cleanCurrent)
                || (cleanOther.contains(cleanCurrent) && cleanCurrent.count >= 6)
                || (cleanCurrent.contains(cleanOther) && cleanOther.count >= 6)
                || (!cleanOtherEn.isEmpty && cleanOtherEn == cleanFranchiseRoot(anime.englishTitle ?? ""))

            if matches {
                let relType = Self.deduceRelationType(current: anime, other: other)
                items.append(
                    RelatedAnimeItem(
                        malID: other.malID,
                        relationType: relType,
                        title: other.title,
                        englishTitle: other.englishTitle,
                        japaneseTitle: other.japaneseTitle,
                        coverImageURL: other.coverImageRemoteURL,
                        format: "TV",
                        status: other.airingStatusRaw,
                        episodes: other.totalEpisodes,
                        seasonYear: Self.extractYear(from: other),
                        synopsis: other.synopsis
                    )
                )
            }
        }

        return items
    }

    private static let cleanPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "\\d+(st|nd|rd|th)\\s+season", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "season\\s+\\d+", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "part\\s+\\d+", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "cour\\s+\\d+", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "the\\s+movie.*", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "[:!?,.-]+", options: .caseInsensitive)
    ]
    private static let yearRegex = try! NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")
    private static let partRegex = try! NSRegularExpression(pattern: "(part|cour)\\s*(\\d+)", options: .caseInsensitive)
    private static let seasonRegex = try! NSRegularExpression(pattern: "(season|part|cour)\\s*(\\d+)", options: .caseInsensitive)
    private static let ordinalSeasonRegex = try! NSRegularExpression(pattern: "(\\d+)(st|nd|rd|th)\\s*season", options: .caseInsensitive)

    private nonisolated static func extractYear(from anime: LibraryMatchSnapshot) -> Int? {
        guard let s = anime.seasonYear else { return nil }
        let range = NSRange(location: 0, length: s.utf16.count)
        if let match = yearRegex.firstMatch(in: s, options: [], range: range),
           let r = Range(match.range, in: s) {
            return Int(s[r])
        }
        return nil
    }

    public nonisolated func cleanFranchiseRoot(_ raw: String) -> String {
        var str = raw.lowercased()
        for regex in Self.cleanPatterns {
            let range = NSRange(location: 0, length: str.utf16.count)
            str = regex.stringByReplacingMatches(in: str, options: [], range: range, withTemplate: " ")
        }
        return str.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func deduceRelationType(current: LibraryMatchSnapshot, other: LibraryMatchSnapshot) -> String {
        let currentSeason = extractSeasonNumber(current.title) ?? extractSeasonNumber(current.englishTitle ?? "")
        let otherSeason = extractSeasonNumber(other.title) ?? extractSeasonNumber(other.englishTitle ?? "")

        if let c = currentSeason, let o = otherSeason {
            if o < c { return "PREQUEL" }
            if o > c { return "SEQUEL" }

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

    private nonisolated static func extractPartNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        let range = NSRange(location: 0, length: lower.utf16.count)
        if let match = partRegex.firstMatch(in: lower, options: [], range: range),
           match.numberOfRanges > 2,
           let r = Range(match.range(at: 2), in: lower) {
            return Int(lower[r])
        }
        return nil
    }

    private nonisolated static func extractSeasonNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        let range = NSRange(location: 0, length: lower.utf16.count)
        if let match = seasonRegex.firstMatch(in: lower, options: [], range: range),
           match.numberOfRanges > 2,
           let r = Range(match.range(at: 2), in: lower) {
            return Int(lower[r])
        }
        if let match = ordinalSeasonRegex.firstMatch(in: lower, options: [], range: range),
           match.numberOfRanges > 1,
           let r = Range(match.range(at: 1), in: lower) {
            return Int(lower[r])
        }
        return nil
    }

    // MARK: - Memory & Disk Cache Helpers

    private func storeRelationsInMemory(_ items: [RelatedAnimeItem], for malID: Int) {
        if cache[malID] == nil {
            cacheOrder.append(malID)
        }
        cache[malID] = items
        if cacheOrder.count > Self.maxMemoryEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func storeFranchiseInMemory(_ items: [RelatedAnimeItem], for malID: Int) {
        if franchiseCache[malID] == nil {
            franchiseCacheOrder.append(malID)
        }
        franchiseCache[malID] = items
        if franchiseCacheOrder.count > Self.maxMemoryEntries {
            let evicted = franchiseCacheOrder.removeFirst()
            franchiseCache.removeValue(forKey: evicted)
        }
    }

    private func loadDiskItems(from directory: URL, for malID: Int, ignoreExpiration: Bool = false) -> [RelatedAnimeItem]? {
        let fileURL = directory.appendingPathComponent("\(malID).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(DiskCacheEnvelope.self, from: data) {
            if ignoreExpiration || Date().timeIntervalSince(envelope.cachedAt) < Self.cacheTTL {
                return envelope.items
            }
            return nil
        }

        // Legacy compatibility: bare [RelatedAnimeItem] array without TTL wrapper
        if let legacyItems = try? decoder.decode([RelatedAnimeItem].self, from: data) {
            return legacyItems
        }

        return nil
    }

    private func saveDiskItems(_ items: [RelatedAnimeItem], to directory: URL, for malID: Int) {
        guard !items.isEmpty else { return }
        let fileURL = directory.appendingPathComponent("\(malID).json")
        let envelope = DiskCacheEnvelope(cachedAt: Date(), items: items)
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Preloads or injects relations into memory and disk cache (useful for tests/previews).
    public func setCachedRelations(_ relations: [RelatedAnimeItem], for malID: Int) {
        storeRelationsInMemory(relations, for: malID)
        saveDiskItems(relations, to: cacheDirectory, for: malID)
    }

    /// Preloads or injects franchise entries into memory and disk cache.
    public func setCachedFranchise(_ franchise: [RelatedAnimeItem], for malID: Int) {
        storeFranchiseInMemory(franchise, for: malID)
        saveDiskItems(franchise, to: franchiseDirectory, for: malID)
    }

    /// Clears the in-memory relations and franchise caches.
    public func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
        franchiseCache.removeAll()
        franchiseCacheOrder.removeAll()
    }
}
