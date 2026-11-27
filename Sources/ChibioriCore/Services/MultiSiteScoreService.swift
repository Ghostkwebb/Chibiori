import Foundation
import SwiftUI

/// User preference for which rating platform is highlighted on library & discover cards.
public enum ScoreDisplayPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case mal = "mal"
    case aniList = "aniList"
    case shikimori = "shikimori"
    case kitsu = "kitsu"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto (MAL First)"
        case .mal: return "MyAnimeList"
        case .aniList: return "AniList"
        case .shikimori: return "Shikimori"
        case .kitsu: return "Kitsu"
        }
    }

    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .mal: return "MAL"
        case .aniList: return "AniList"
        case .shikimori: return "Shikimori"
        case .kitsu: return "Kitsu"
        }
    }

    public var preferredSource: ScoreSource? {
        switch self {
        case .auto: return nil
        case .mal: return .mal
        case .aniList: return .aniList
        case .shikimori: return .shikimori
        case .kitsu: return .kitsu
        }
    }
}

/// Supported external anime rating platforms resolved by MyAnimeList ID.
public enum ScoreSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case mal
    case aniList
    case kitsu
    case shikimori

    public var id: String { rawValue }

    public var shortCode: String {
        switch self {
        case .mal: return "MAL"
        case .aniList: return "AL"
        case .kitsu: return "KT"
        case .shikimori: return "SHK"
        }
    }

    public var displayName: String {
        switch self {
        case .mal: return "MyAnimeList"
        case .aniList: return "AniList"
        case .kitsu: return "Kitsu"
        case .shikimori: return "Shikimori"
        }
    }

    public var brandColor: Color {
        switch self {
        case .mal: return Color(red: 0.22, green: 0.38, blue: 0.78)
        case .aniList: return Color(red: 0.05, green: 0.64, blue: 0.96)
        case .kitsu: return Color(red: 0.95, green: 0.36, blue: 0.26)
        case .shikimori: return Color(red: 0.45, green: 0.48, blue: 0.90)
        }
    }

    public func pageURL(malID: Int, aniListID: Int? = nil, kitsuSlug: String? = nil) -> URL? {
        switch self {
        case .mal:
            guard malID > 0 else { return nil }
            return URL(string: "https://myanimelist.net/anime/\(malID)")
        case .aniList:
            guard let aniListID, aniListID > 0 else { return nil }
            return URL(string: "https://anilist.co/anime/\(aniListID)")
        case .kitsu:
            guard let kitsuSlug, !kitsuSlug.isEmpty else { return nil }
            return URL(string: "https://kitsu.io/anime/\(kitsuSlug)")
        case .shikimori:
            guard malID > 0 else { return nil }
            return URL(string: "https://shikimori.io/animes/\(malID)")
        }
    }
}

/// Cached multi-website scores normalized to a 0...10 scale for a single anime.
public struct AnimeSiteScores: Codable, Sendable, Equatable {
    public let malID: Int
    public var malScore: Double?
    public var aniListScore: Double?
    public var kitsuScore: Double?
    public var shikimoriScore: Double?
    public var aniListID: Int?
    public var kitsuSlug: String?
    public var hasFetchedAllProviders: Bool
    public var updatedAt: Date

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.malID = try container.decode(Int.self, forKey: .malID)
        self.malScore = try container.decodeIfPresent(Double.self, forKey: .malScore)
        self.aniListScore = try container.decodeIfPresent(Double.self, forKey: .aniListScore)
        self.kitsuScore = try container.decodeIfPresent(Double.self, forKey: .kitsuScore)
        self.shikimoriScore = try container.decodeIfPresent(Double.self, forKey: .shikimoriScore)
        self.aniListID = try container.decodeIfPresent(Int.self, forKey: .aniListID)
        self.kitsuSlug = try container.decodeIfPresent(String.self, forKey: .kitsuSlug)
        self.hasFetchedAllProviders = try container.decodeIfPresent(Bool.self, forKey: .hasFetchedAllProviders) ?? false
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public init(
        malID: Int,
        malScore: Double? = nil,
        aniListScore: Double? = nil,
        kitsuScore: Double? = nil,
        shikimoriScore: Double? = nil,
        aniListID: Int? = nil,
        kitsuSlug: String? = nil,
        hasFetchedAllProviders: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.malID = malID
        self.malScore = malScore
        self.aniListScore = aniListScore
        self.kitsuScore = kitsuScore
        self.shikimoriScore = shikimoriScore
        self.aniListID = aniListID
        self.kitsuSlug = kitsuSlug
        self.hasFetchedAllProviders = hasFetchedAllProviders
        self.updatedAt = updatedAt
    }

    public var entries: [(source: ScoreSource, score: Double)] {
        var list: [(ScoreSource, Double)] = []
        if let malScore, malScore > 0 { list.append((.mal, malScore)) }
        if let aniListScore, aniListScore > 0 { list.append((.aniList, aniListScore)) }
        if let shikimoriScore, shikimoriScore > 0 { list.append((.shikimori, shikimoriScore)) }
        if let kitsuScore, kitsuScore > 0 { list.append((.kitsu, kitsuScore)) }
        return list
    }

    public func score(for source: ScoreSource) -> Double? {
        switch source {
        case .mal: return (malScore ?? 0) > 0 ? malScore : nil
        case .aniList: return (aniListScore ?? 0) > 0 ? aniListScore : nil
        case .shikimori: return (shikimoriScore ?? 0) > 0 ? shikimoriScore : nil
        case .kitsu: return (kitsuScore ?? 0) > 0 ? kitsuScore : nil
        }
    }

    /// Preferred score badge ordered by user preference, with automatic fallback if unavailable.
    public var primaryCardBadge: (source: ScoreSource, score: Double)? {
        badge(for: .auto)
    }

    public func badge(for preference: ScoreDisplayPreference) -> (source: ScoreSource, score: Double)? {
        let order: [ScoreSource]
        switch preference {
        case .auto, .mal:
            order = [.mal, .aniList, .shikimori, .kitsu]
        case .aniList:
            order = [.aniList, .mal, .shikimori, .kitsu]
        case .shikimori:
            order = [.shikimori, .mal, .aniList, .kitsu]
        case .kitsu:
            order = [.kitsu, .mal, .aniList, .shikimori]
        }

        for src in order {
            if let value = score(for: src) {
                return (src, value)
            }
        }
        return nil
    }

    public static func formatScore(_ score: Double, for source: ScoreSource, compact: Bool = false) -> String {
        if compact {
            return String(format: "%.1f", score)
        }
        switch source {
        case .aniList:
            let roundedTenths = (score * 10).rounded() / 10
            if abs(score - roundedTenths) < 0.005 {
                return String(format: "%.1f", score)
            }
            return String(format: "%.2f", score)
        case .mal, .kitsu, .shikimori:
            return String(format: "%.2f", score)
        }
    }
}

/// Fetches and caches community ratings across MyAnimeList, AniList, Kitsu, and Shikimori.
public actor MultiSiteScoreService {
    public static let shared = MultiSiteScoreService()

    private static let cacheTTL: TimeInterval = 24 * 3600 // 24 hours
    private static let maxCachedEntries = 1000

    private static let malRatingValueRegex = try! NSRegularExpression(
        pattern: #"itemprop=["']ratingValue["'][^>]*>([0-9]+(?:\.[0-9]+)?)"#,
        options: .caseInsensitive
    )
    private static let malScoreLabelRegex = try! NSRegularExpression(
        pattern: #"class=["']score-label[^"']*["'][^>]*>([0-9]+(?:\.[0-9]+)?)"#,
        options: .caseInsensitive
    )

    private var cache: [Int: AnimeSiteScores] = [:]
    private var cacheOrder: [Int] = []
    private var inFlightTasks: [Int: Task<AnimeSiteScores, Never>] = [:]
    private var isCacheLoaded = false
    private var saveTask: Task<Void, Never>?

    private let cacheFileURL: URL
    private let session: URLSession
    private let aniList: AniListClient

    public init(
        cacheFileURL: URL? = nil,
        session: URLSession = .shared,
        aniList: AniListClient = .shared
    ) {
        if let cacheFileURL {
            self.cacheFileURL = cacheFileURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.cacheFileURL = caches
                .appendingPathComponent("Chibiori", isDirectory: true)
                .appendingPathComponent("site_scores_v1.json")
        }
        self.session = session
        self.aniList = aniList
    }

    public func cachedScores(for malID: Int) -> AnimeSiteScores? {
        ensureCacheLoaded()
        return cache[malID]
    }

    public func allCachedScores() -> [Int: AnimeSiteScores] {
        ensureCacheLoaded()
        return cache
    }

    /// Parses the public MyAnimeList HTML community score when Jikan REST is unreachable or slow.
    public nonisolated static func parseMALHTMLScore(from html: String) -> Double? {
        let range = NSRange(location: 0, length: html.utf16.count)
        for regex in [malRatingValueRegex, malScoreLabelRegex] {
            if let match = regex.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: html),
               let score = Double(html[captureRange]),
               score > 0, score <= 10.0 {
                return score
            }
        }
        return nil
    }

    /// Fetches ratings across MAL, AniList, Shikimori, and Kitsu concurrently, streaming partial updates as fast providers finish.
    public func fetchAllScores(
        for malID: Int,
        fallbackAniListScore: Double? = nil,
        forceRefresh: Bool = false,
        onUpdate: (@Sendable (AnimeSiteScores) async -> Void)? = nil
    ) async -> AnimeSiteScores {
        guard malID > 0 else {
            return AnimeSiteScores(malID: malID, aniListScore: fallbackAniListScore)
        }

        ensureCacheLoaded()

        if !forceRefresh,
           let existing = cache[malID],
           Date().timeIntervalSince(existing.updatedAt) < Self.cacheTTL,
           existing.hasFetchedAllProviders {
            return existing
        }

        if let existingTask = inFlightTasks[malID] {
            return await existingTask.value
        }

        let previous = cache[malID]
        let task = Task<AnimeSiteScores, Never> {
            enum PartialResult: Sendable {
                case mal(Double?)
                case aniList(id: Int?, score: Double?)
                case kitsu(slug: String?, score: Double?)
                case shikimori(Double?)
            }

            var current = AnimeSiteScores(
                malID: malID,
                malScore: previous?.malScore,
                aniListScore: previous?.aniListScore ?? fallbackAniListScore,
                kitsuScore: previous?.kitsuScore,
                shikimoriScore: previous?.shikimoriScore,
                aniListID: previous?.aniListID,
                kitsuSlug: previous?.kitsuSlug,
                hasFetchedAllProviders: false,
                updatedAt: Date()
            )

            await withTaskGroup(of: PartialResult.self) { group in
                group.addTask {
                    .mal(await self.fetchMALScore(malID: malID))
                }
                group.addTask {
                    let info = await self.aniList.fetchScoreInfo(malId: malID)
                    return .aniList(id: info?.aniListID, score: info?.score)
                }
                group.addTask {
                    .shikimori(await self.fetchShikimoriScore(malID: malID))
                }
                group.addTask {
                    let info = await self.fetchKitsuScore(malID: malID)
                    return .kitsu(slug: info?.slug, score: info?.score)
                }

                for await partial in group {
                    var changed = false
                    switch partial {
                    case .mal(let score):
                        if let score, score > 0, current.malScore != score {
                            current.malScore = score
                            changed = true
                        }
                    case .aniList(let id, let score):
                        if let id, current.aniListID != id {
                            current.aniListID = id
                            changed = true
                        }
                        if let score, score > 0, current.aniListScore != score {
                            current.aniListScore = score
                            changed = true
                        }
                    case .kitsu(let slug, let score):
                        if let slug, current.kitsuSlug != slug {
                            current.kitsuSlug = slug
                            changed = true
                        }
                        if let score, score > 0, current.kitsuScore != score {
                            current.kitsuScore = score
                            changed = true
                        }
                    case .shikimori(let score):
                        if let score, score > 0, current.shikimoriScore != score {
                            current.shikimoriScore = score
                            changed = true
                        }
                    }

                    if changed {
                        current.updatedAt = Date()
                        if let onUpdate {
                            await onUpdate(current)
                        }
                    }
                }
            }

            current.hasFetchedAllProviders = true
            return current
        }

        inFlightTasks[malID] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: malID)

        if !result.entries.isEmpty {
            storeInCache(result)
            scheduleDiskSave()
        }

        return result
    }

    /// Batch-hydrates missing scores across the active filtered list, streaming batches progressively so cards update quickly.
    public func prefetchBatchScores(
        for malIDs: [Int],
        preference: ScoreDisplayPreference,
        onBatchUpdate: (@Sendable ([Int: AnimeSiteScores]) async -> Void)? = nil
    ) async -> [Int: AnimeSiteScores] {
        ensureCacheLoaded()

        var seen = Set<Int>()
        let uniqueIDs = malIDs.filter { id in
            guard id > 0, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
        guard !uniqueIDs.isEmpty else { return [:] }

        let targetSource = preference.preferredSource
        let missingIDs = Array(uniqueIDs.filter { id in
            guard let existing = cache[id] else { return true }
            if let targetSource {
                return existing.score(for: targetSource) == nil
            }
            return existing.malScore == nil
        }.prefix(100))

        guard !missingIDs.isEmpty else { return [:] }

        var allUpdated: [Int: AnimeSiteScores] = [:]

        // 1. Fast GraphQL batch queries (chunks of 45) for AniList & Shikimori
        if preference == .aniList || preference == .auto {
            for start in stride(from: 0, to: missingIDs.count, by: 45) {
                if Task.isCancelled { break }
                let chunk = Array(missingIDs[start..<min(start + 45, missingIDs.count)])
                let aniNodes = await aniList.fetchBatchMetadata(malIDs: chunk)
                var chunkMap: [Int: AnimeSiteScores] = [:]
                for node in aniNodes {
                    guard let idMal = node.idMal, let avg = node.averageScore, avg > 0 else { continue }
                    var entry = cache[idMal] ?? AnimeSiteScores(malID: idMal)
                    entry.aniListScore = avg / 10.0
                    entry.updatedAt = Date()
                    storeInCache(entry)
                    chunkMap[idMal] = entry
                    allUpdated[idMal] = entry
                }
                if !chunkMap.isEmpty, let onBatchUpdate {
                    await onBatchUpdate(chunkMap)
                }
            }
        }

        if preference == .shikimori {
            for start in stride(from: 0, to: missingIDs.count, by: 45) {
                if Task.isCancelled { break }
                let chunk = Array(missingIDs[start..<min(start + 45, missingIDs.count)])
                let shikiScores = await fetchShikimoriBatchScores(malIDs: chunk)
                var chunkMap: [Int: AnimeSiteScores] = [:]
                for (idMal, score) in shikiScores {
                    var entry = cache[idMal] ?? AnimeSiteScores(malID: idMal)
                    entry.shikimoriScore = score
                    entry.updatedAt = Date()
                    storeInCache(entry)
                    chunkMap[idMal] = entry
                    allUpdated[idMal] = entry
                }
                if !chunkMap.isEmpty, let onBatchUpdate {
                    await onBatchUpdate(chunkMap)
                }
            }
        }

        // 2. Concurrent MAL / Kitsu hydration across all missing items in current view (max 6 concurrent)
        if preference == .mal || preference == .kitsu || preference == .auto {
            var nextIndex = 0
            let maxConcurrent = 6
            var pendingFlush: [Int: AnimeSiteScores] = [:]

            await withTaskGroup(of: AnimeSiteScores.self) { group in
                let initial = min(maxConcurrent, missingIDs.count)
                while nextIndex < initial {
                    let id = missingIDs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        if Task.isCancelled { return AnimeSiteScores(malID: id) }
                        if preference == .kitsu {
                            let info = await self.fetchKitsuScore(malID: id)
                            var entry = await self.cachedOrEmpty(id)
                            if let slug = info?.slug { entry.kitsuSlug = slug }
                            if let score = info?.score, score > 0 { entry.kitsuScore = score }
                            return entry
                        } else {
                            let malScore = await self.fetchMALScore(malID: id)
                            var entry = await self.cachedOrEmpty(id)
                            if let malScore, malScore > 0 { entry.malScore = malScore }
                            return entry
                        }
                    }
                }

                for await entry in group {
                    if !entry.entries.isEmpty {
                        storeInCache(entry)
                        allUpdated[entry.malID] = entry
                        pendingFlush[entry.malID] = entry
                    }

                    if pendingFlush.count >= 6, let onBatchUpdate {
                        let flushBatch = pendingFlush
                        pendingFlush.removeAll()
                        await onBatchUpdate(flushBatch)
                    }

                    if !Task.isCancelled && nextIndex < missingIDs.count {
                        let id = missingIDs[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            if Task.isCancelled { return AnimeSiteScores(malID: id) }
                            if preference == .kitsu {
                                let info = await self.fetchKitsuScore(malID: id)
                                var entry = await self.cachedOrEmpty(id)
                                if let slug = info?.slug { entry.kitsuSlug = slug }
                                if let score = info?.score, score > 0 { entry.kitsuScore = score }
                                return entry
                            } else {
                                let malScore = await self.fetchMALScore(malID: id)
                                var entry = await self.cachedOrEmpty(id)
                                if let malScore, malScore > 0 { entry.malScore = malScore }
                                return entry
                            }
                        }
                    }
                }
            }

            if !pendingFlush.isEmpty, let onBatchUpdate {
                await onBatchUpdate(pendingFlush)
            }
        }

        if !allUpdated.isEmpty {
            scheduleDiskSave()
        }
        return allUpdated
    }

    private func cachedOrEmpty(_ malID: Int) -> AnimeSiteScores {
        cache[malID] ?? AnimeSiteScores(malID: malID)
    }

    // MARK: - Provider Lookups

    private struct JikanScoreResponse: Decodable {
        struct Payload: Decodable {
            let score: Double?
        }
        let data: Payload?
    }

    /// Races Jikan API (fast when healthy) with public MAL page metadata so unreachable Jikan mirrors never stall the UI.
    private func fetchMALScore(malID: Int) async -> Double? {
        await withTaskGroup(of: Double?.self) { group in
            group.addTask {
                await self.fetchJikanMALScore(malID: malID)
            }
            group.addTask {
                await self.fetchDirectMALPageScore(malID: malID)
            }

            for await candidate in group {
                if let score = candidate, score > 0 {
                    group.cancelAll()
                    return score
                }
            }
            return nil
        }
    }

    private func fetchJikanMALScore(malID: Int) async -> Double? {
        guard let url = URL(string: "https://api.jikan.moe/v4/anime/\(malID)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 2.5)
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(JikanScoreResponse.self, from: data),
              let score = decoded.data?.score,
              score > 0 else {
            return nil
        }
        return score
    }

    private func fetchDirectMALPageScore(malID: Int) async -> Double? {
        guard let url = URL(string: "https://myanimelist.net/anime/\(malID)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 3.5)
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.parseMALHTMLScore(from: html)
    }

    private struct KitsuMappingsResponse: Decodable {
        struct IncludedItem: Decodable {
            struct Attributes: Decodable {
                let slug: String?
                let averageRating: String?
            }
            let type: String?
            let attributes: Attributes?
        }
        let included: [IncludedItem]?
    }

    private func fetchKitsuScore(malID: Int) async -> (slug: String?, score: Double?)? {
        guard let url = URL(string: "https://kitsu.io/api/edge/mappings?filter%5BexternalSite%5D=myanimelist/anime&filter%5BexternalId%5D=\(malID)&include=item") else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 3.5)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(KitsuMappingsResponse.self, from: data),
              let animeItem = decoded.included?.first(where: { ($0.type ?? "anime") == "anime" }) else {
            return nil
        }

        let slug = animeItem.attributes?.slug
        guard let rawStr = animeItem.attributes?.averageRating,
              let rawVal = Double(rawStr),
              rawVal > 0 else {
            return (slug, nil)
        }
        let normalized = rawVal > 10.0 ? (rawVal / 10.0) : rawVal
        return (slug, normalized)
    }

    private struct ShikimoriAnimeResponse: Decodable {
        let id: Int?
        let score: String?
    }

    private func fetchShikimoriScore(malID: Int) async -> Double? {
        guard let url = URL(string: "https://shikimori.io/api/animes/\(malID)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 3.5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ShikimoriAnimeResponse.self, from: data),
              let rawScore = decoded.score,
              let value = Double(rawScore),
              value > 0 else {
            return nil
        }
        return value
    }

    private struct ShikimoriGraphQLResponse: Decodable {
        struct DataNode: Decodable {
            struct AnimeNode: Decodable {
                let malId: String?
                let score: Double?
            }
            let animes: [AnimeNode]?
        }
        let data: DataNode?
    }

    private func fetchShikimoriBatchScores(malIDs: [Int]) async -> [Int: Double] {
        guard !malIDs.isEmpty,
              let url = URL(string: "https://shikimori.io/api/graphql") else {
            return [:]
        }
        let idList = malIDs.map(String.init).joined(separator: ",")
        let payloadDict: [String: Any] = [
            "query": "query($ids: String, $limit: PositiveInt){ animes(ids: $ids, limit: $limit) { malId score } }",
            "variables": ["ids": idList, "limit": min(50, malIDs.count)]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payloadDict) else { return [:] }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 4.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = httpBody

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ShikimoriGraphQLResponse.self, from: data) else {
            return [:]
        }

        var result: [Int: Double] = [:]
        for item in decoded.data?.animes ?? [] {
            if let malStr = item.malId, let malId = Int(malStr), let score = item.score, score > 0 {
                result[malId] = score
            }
        }
        return result
    }

    // MARK: - Persistence

    private func ensureCacheLoaded() {
        guard !isCacheLoaded else { return }
        isCacheLoaded = true

        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([Int: AnimeSiteScores].self, from: data) else {
            return
        }
        self.cache = decoded
        self.cacheOrder = Array(decoded.keys)
    }

    private func storeInCache(_ scores: AnimeSiteScores) {
        if cache[scores.malID] == nil {
            cacheOrder.append(scores.malID)
        }
        cache[scores.malID] = scores
        if cacheOrder.count > Self.maxCachedEntries {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    private func scheduleDiskSave() {
        saveTask?.cancel()
        let snapshot = cache
        let targetURL = cacheFileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let dir = targetURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }
}
