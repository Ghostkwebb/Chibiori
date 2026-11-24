import Foundation
import Observation

public struct ParentAnimeInfo: Sendable {
    public let malID: Int
    public let title: String
    public let english: String?
    public let native: String?

    public init(malID: Int = 0, title: String, english: String? = nil, native: String? = nil) {
        self.malID = malID
        self.title = title
        self.english = english
        self.native = native
    }
}

public struct SequelAlertItem: Identifiable, Sendable, Codable, Equatable {
    public var id: Int { sequelMalId }
    public let parentMalId: Int
    public let parentTitle: String
    public let parentEnglishTitle: String?
    public let parentJapaneseTitle: String?
    public let sequelMalId: Int
    public let sequelTitle: String
    public let sequelEnglishTitle: String?
    public let sequelJapaneseTitle: String?
    public let sequelCoverImageURL: String
    public let sequelStatus: String
    public let airingSeasonYear: String?
    public let synopsis: String?
    public let detectedAt: Date

    public init(
        parentMalId: Int,
        parentTitle: String,
        parentEnglishTitle: String? = nil,
        parentJapaneseTitle: String? = nil,
        sequelMalId: Int,
        sequelTitle: String,
        sequelEnglishTitle: String? = nil,
        sequelJapaneseTitle: String? = nil,
        sequelCoverImageURL: String = "",
        sequelStatus: String = "NOT_YET_RELEASED",
        airingSeasonYear: String? = nil,
        synopsis: String? = nil,
        detectedAt: Date = Date()
    ) {
        self.parentMalId = parentMalId
        self.parentTitle = parentTitle
        self.parentEnglishTitle = parentEnglishTitle
        self.parentJapaneseTitle = parentJapaneseTitle
        self.sequelMalId = sequelMalId
        self.sequelTitle = sequelTitle
        self.sequelEnglishTitle = sequelEnglishTitle
        self.sequelJapaneseTitle = sequelJapaneseTitle
        self.sequelCoverImageURL = sequelCoverImageURL
        self.sequelStatus = sequelStatus
        self.airingSeasonYear = airingSeasonYear
        self.synopsis = synopsis
        self.detectedAt = detectedAt
    }

    public func displaySequelTitle(for preference: TitleLanguagePreference = .english) -> String {
        resolveDisplayTitle(for: preference, fallback: "Upcoming Sequel")
    }

    public func displayParentTitle(for preference: TitleLanguagePreference = .english) -> String {
        switch preference {
        case .english:
            return parentEnglishTitle?.isEmpty == false ? parentEnglishTitle! : parentTitle
        case .romaji:
            return parentTitle
        case .native:
            return parentJapaneseTitle?.isEmpty == false ? parentJapaneseTitle! : parentTitle
        }
    }

    public var asJikanDTO: JikanAnimeDTO {
        let images = JikanImagesDTO(
            jpg: JikanImageFormatDTO(imageUrl: sequelCoverImageURL, smallImageUrl: nil, largeImageUrl: sequelCoverImageURL),
            webp: JikanImageFormatDTO(imageUrl: sequelCoverImageURL, smallImageUrl: nil, largeImageUrl: sequelCoverImageURL)
        )
        return JikanAnimeDTO(
            malId: sequelMalId,
            title: sequelTitle,
            titleEnglish: sequelEnglishTitle,
            titleJapanese: sequelJapaneseTitle,
            synopsis: synopsis,
            images: images,
            status: sequelStatus,
            year: nil
        )
    }
}

extension SequelAlertItem: TitleResolvable {
    public var primaryRomajiTitle: String { sequelTitle }
    public var optionalEnglishTitle: String? { sequelEnglishTitle }
    public var optionalNativeTitle: String? { sequelJapaneseTitle }
}

/// Scans completed library entries for announced or airing sequels and persists alert snapshots to cache storage.
@Observable
@MainActor
public final class SequelAlertService {
    public static let shared = SequelAlertService()

    private static let legacyDefaultsKey = "savedSequelAlertsData"

    public var alerts: [SequelAlertItem] = [] {
        didSet {
            if !isLoadingFromDisk {
                saveAlertsToCache()
            }
        }
    }
    public var isScanning: Bool = false
    public var lastScannedDate: Date? = nil

    private let cacheFileURL: URL
    private let defaults: UserDefaults
    private let aniList: AniListClient
    private var isLoadingFromDisk = false

    public init(
        cacheFileURL: URL? = nil,
        defaults: UserDefaults = .standard,
        aniList: AniListClient = .shared
    ) {
        if let cacheFileURL {
            self.cacheFileURL = cacheFileURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.cacheFileURL = caches
                .appendingPathComponent("Chibiori", isDirectory: true)
                .appendingPathComponent("sequel_alerts.json")
        }
        self.defaults = defaults
        self.aniList = aniList
        loadAlertsFromCache()
    }

    private func saveAlertsToCache() {
        let snapshot = alerts
        let destination = cacheFileURL
        Task.detached(priority: .utility) {
            let parentDir = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }

    private func loadAlertsFromCache() {
        isLoadingFromDisk = true
        defer { isLoadingFromDisk = false }

        if let data = try? Data(contentsOf: cacheFileURL),
           let cached = try? JSONDecoder().decode([SequelAlertItem].self, from: data) {
            self.alerts = cached
            return
        }

        // One-time migration from legacy UserDefaults storage
        if let legacyData = defaults.data(forKey: Self.legacyDefaultsKey),
           let cached = try? JSONDecoder().decode([SequelAlertItem].self, from: legacyData) {
            self.alerts = cached
            let destination = cacheFileURL
            let parentDir = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try? legacyData.write(to: destination, options: .atomic)
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
        }
    }

    /// Scans `TrackedAnime` completed entries for upcoming or recent sequels.
    public func scanForSequels(completedAnime: [TrackedAnime], existingTrackedIDs: Set<Int>) async {
        let parentItems = completedAnime
            .filter { $0.malID > 0 }
            .map {
                ParentAnimeInfo(
                    malID: $0.malID,
                    title: $0.title,
                    english: $0.englishTitle,
                    native: $0.japaneseTitle
                )
            }
        await scanForSequels(completedItems: parentItems, existingTrackedIDs: existingTrackedIDs)
    }

    /// Scans pre-extracted parent items in capped-concurrency batches of 45 MAL IDs.
    public func scanForSequels(completedItems: [ParentAnimeInfo], existingTrackedIDs: Set<Int>) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        var alertMap: [Int: SequelAlertItem] = [:]
        for item in alerts {
            alertMap[item.sequelMalId] = item
        }

        var parentAnimeMap: [Int: ParentAnimeInfo] = [:]
        var malIDs: [Int] = []
        for item in completedItems where item.malID > 0 {
            parentAnimeMap[item.malID] = item
            malIDs.append(item.malID)
        }

        let chunkSize = 45
        let chunks = stride(from: 0, to: malIDs.count, by: chunkSize).map {
            Array(malIDs[$0..<min($0 + chunkSize, malIDs.count)])
        }

        let minimumRecentYear = Calendar.current.component(.year, from: Date()) - 1
        let maxConcurrent = 2
        var nextChunkIndex = 0

        await withTaskGroup(of: [SequelAlertItem].self) { group in
            let initialCount = min(maxConcurrent, chunks.count)
            while nextChunkIndex < initialCount {
                let chunk = chunks[nextChunkIndex]
                nextChunkIndex += 1
                group.addTask {
                    await self.queryBatchRelations(
                        for: chunk,
                        parentAnimeMap: parentAnimeMap,
                        minimumRecentYear: minimumRecentYear
                    )
                }
            }

            for await batchResults in group {
                for item in batchResults {
                    alertMap[item.sequelMalId] = item
                }
                if nextChunkIndex < chunks.count {
                    let chunk = chunks[nextChunkIndex]
                    nextChunkIndex += 1
                    group.addTask {
                        await self.queryBatchRelations(
                            for: chunk,
                            parentAnimeMap: parentAnimeMap,
                            minimumRecentYear: minimumRecentYear
                        )
                    }
                }
            }
        }

        self.alerts = Array(alertMap.values).sorted {
            ($0.airingSeasonYear ?? "") < ($1.airingSeasonYear ?? "")
        }
        self.lastScannedDate = Date()
    }

    private nonisolated func queryBatchRelations(
        for malIDs: [Int],
        parentAnimeMap: [Int: ParentAnimeInfo],
        minimumRecentYear: Int
    ) async -> [SequelAlertItem] {
        let mediaList = await aniList.fetchBatchRelations(malIDs: malIDs)
        var items: [SequelAlertItem] = []

        for media in mediaList {
            guard let parentMalId = media.idMal else { continue }
            let parentInfo = parentAnimeMap[parentMalId]
            let parentTitle = parentInfo?.title ?? (media.title?.romaji ?? "")
            let parentEnglish = parentInfo?.english ?? media.title?.english
            let parentNative = parentInfo?.native ?? media.title?.native

            for edge in media.relations?.edges ?? [] {
                let relType = edge.relationType ?? ""
                guard relType == "SEQUEL" || relType == "SIDE_STORY" || relType == "ALTERNATIVE" else { continue }
                guard let node = edge.node else { continue }

                let status = node.status ?? ""
                let seasonYear = node.seasonYear
                let isUpcoming = (status == "NOT_YET_RELEASED" || status == "RELEASING")
                let isRecentYear = (seasonYear ?? 0) >= minimumRecentYear

                guard isUpcoming || isRecentYear else { continue }

                let sequelMal = (node.idMal ?? 0) > 0 ? (node.idMal ?? 0) : (node.id ?? 0)
                guard sequelMal > 0, sequelMal != parentMalId else { continue }

                let romaji = node.title?.romaji ?? "Upcoming Sequel"
                var resolvedEnglish = node.title?.english
                if resolvedEnglish == nil || resolvedEnglish?.isEmpty == true {
                    for syn in node.synonyms ?? [] {
                        let trimmed = syn.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.canBeConverted(to: .ascii), trimmed.count >= 2 {
                            resolvedEnglish = trimmed
                            break
                        }
                    }
                }

                let airingFormatted: String?
                if let s = node.season?.capitalized, let y = seasonYear {
                    airingFormatted = "\(s) \(y)"
                } else if let y = seasonYear {
                    airingFormatted = "\(y)"
                } else {
                    airingFormatted = nil
                }

                items.append(
                    SequelAlertItem(
                        parentMalId: parentMalId,
                        parentTitle: parentTitle,
                        parentEnglishTitle: parentEnglish,
                        parentJapaneseTitle: parentNative,
                        sequelMalId: sequelMal,
                        sequelTitle: romaji,
                        sequelEnglishTitle: resolvedEnglish,
                        sequelJapaneseTitle: node.title?.native,
                        sequelCoverImageURL: node.coverImage?.large ?? "",
                        sequelStatus: status,
                        airingSeasonYear: airingFormatted,
                        synopsis: HTMLCleaner.strip(from: node.description)
                    )
                )
            }
        }

        return items
    }
}
