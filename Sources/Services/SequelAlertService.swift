import Foundation
import SwiftData
import Observation

public struct ParentAnimeInfo: Sendable {
    public let title: String
    public let english: String?
    public let native: String?

    public init(title: String, english: String? = nil, native: String? = nil) {
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
        sequelCoverImageURL: String,
        sequelStatus: String,
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
        switch preference {
        case .english:
            if let en = sequelEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if !sequelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sequelTitle
            }
            if let jp = sequelJapaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Upcoming Sequel"
        case .romaji:
            if !sequelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sequelTitle
            }
            if let en = sequelEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if let jp = sequelJapaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Upcoming Sequel"
        case .native:
            if let jp = sequelJapaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            if !sequelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sequelTitle
            }
            if let en = sequelEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            return "Upcoming Sequel"
        }
    }

    public func displayParentTitle(for preference: TitleLanguagePreference = .english) -> String {
        switch preference {
        case .english:
            if let en = parentEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            return parentTitle
        case .romaji:
            return parentTitle
        case .native:
            if let jp = parentJapaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return parentTitle
        }
    }

    public var asJikanDTO: JikanAnimeDTO {
        let jpg = JikanImageFormatDTO(
            imageUrl: sequelCoverImageURL,
            smallImageUrl: nil,
            largeImageUrl: sequelCoverImageURL
        )
        let images = JikanImagesDTO(jpg: jpg, webp: nil)
        return JikanAnimeDTO(
            malId: sequelMalId,
            title: sequelTitle,
            titleEnglish: sequelEnglishTitle,
            titleJapanese: sequelJapaneseTitle,
            synopsis: synopsis,
            images: images,
            status: sequelStatus == "RELEASING" ? "Currently Airing" : "Not yet aired"
        )
    }
}

@Observable
@MainActor
public final class SequelAlertService {
    public static let shared = SequelAlertService()

    public var alerts: [SequelAlertItem] = [] {
        didSet {
            saveAlertsToCache()
        }
    }
    public var isScanning: Bool = false
    public var lastScannedDate: Date? = nil

    private init() {
        loadAlertsFromCache()
    }

    private func saveAlertsToCache() {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: "savedSequelAlertsData")
        }
    }

    private func loadAlertsFromCache() {
        guard let data = UserDefaults.standard.data(forKey: "savedSequelAlertsData"),
              let cached = try? JSONDecoder().decode([SequelAlertItem].self, from: data) else {
            return
        }
        self.alerts = cached
    }

    /// Scans completed anime list in high-speed batches to detect newly announced or upcoming sequels/seasons
    public func scanForSequels(completedAnime: [TrackedAnime], existingTrackedIDs: Set<Int>) async {
        guard !isScanning else { return }
        isScanning = true

        // Keep existing alerts in a dictionary by sequel ID to merge seamlessly
        var alertMap: [Int: SequelAlertItem] = [:]
        for a in alerts {
            alertMap[a.sequelMalId] = a
        }

        // Build mapping of parent anime by MAL ID
        var map: [Int: ParentAnimeInfo] = [:]
        var ids: [Int] = []
        for anime in completedAnime {
            guard anime.malID > 0 else { continue }
            map[anime.malID] = ParentAnimeInfo(
                title: anime.title,
                english: anime.englishTitle,
                native: anime.japaneseTitle
            )
            ids.append(anime.malID)
        }
        let parentAnimeMap = map
        let malIDs = ids

        // Chunk IDs into batches of 45
        let chunkSize = 45
        let chunks = stride(from: 0, to: malIDs.count, by: chunkSize).map {
            Array(malIDs[$0..<min($0 + chunkSize, malIDs.count)])
        }

        // Execute batch queries in parallel
        await withTaskGroup(of: [SequelAlertItem].self) { group in
            for chunk in chunks {
                group.addTask {
                    await self.queryBatchRelations(for: chunk, parentAnimeMap: parentAnimeMap)
                }
            }

            for await batchResults in group {
                for item in batchResults {
                    alertMap[item.sequelMalId] = item
                }
            }
        }

        self.alerts = Array(alertMap.values).sorted {
            ($0.airingSeasonYear ?? "") < ($1.airingSeasonYear ?? "")
        }
        self.lastScannedDate = Date()
        self.isScanning = false
    }

    private func queryBatchRelations(
        for malIDs: [Int],
        parentAnimeMap: [Int: ParentAnimeInfo]
    ) async -> [SequelAlertItem] {
        let gql = """
        query ($ids: [Int]) {
          Page(page: 1, perPage: 50) {
            media(idMal_in: $ids, type: ANIME) {
              idMal
              title { romaji english native }
              synonyms
              relations {
                edges {
                  relationType
                  node {
                    id
                    idMal
                    title { romaji english native }
                    synonyms
                    status
                    season
                    seasonYear
                    description
                    coverImage { large }
                  }
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

        let bodyDict: [String: Any] = ["query": gql, "variables": ["ids": malIDs]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let pageObj = dataObj["Page"] as? [String: Any],
                  let mediaList = pageObj["media"] as? [[String: Any]] else {
                return []
            }

            var items: [SequelAlertItem] = []

            for media in mediaList {
                guard let parentMalId = media["idMal"] as? Int else { continue }
                let parentInfo = parentAnimeMap[parentMalId]
                let parentTitle = parentInfo?.title ?? ((media["title"] as? [String: Any])?["romaji"] as? String ?? "")
                let parentEnglish = parentInfo?.english ?? ((media["title"] as? [String: Any])?["english"] as? String)
                let parentNative = parentInfo?.native ?? ((media["title"] as? [String: Any])?["native"] as? String)

                guard let relObj = media["relations"] as? [String: Any],
                      let edges = relObj["edges"] as? [[String: Any]] else { continue }

                for edge in edges {
                    let relType = edge["relationType"] as? String ?? ""
                    guard relType == "SEQUEL" || relType == "SIDE_STORY" || relType == "ALTERNATIVE" else { continue }

                    guard let node = edge["node"] as? [String: Any] else { continue }
                    let status = node["status"] as? String ?? ""
                    let season = node["season"] as? String
                    let seasonYear = node["seasonYear"] as? Int

                    // Check if upcoming or newly released sequel
                    let isUpcoming = (status == "NOT_YET_RELEASED" || status == "RELEASING")
                    let isFutureOrRecentYear = (seasonYear ?? 0) >= 2025

                    if isUpcoming || isFutureOrRecentYear {
                        let sequelMal = node["idMal"] as? Int ?? node["id"] as? Int ?? 0
                        guard sequelMal > 0, sequelMal != parentMalId else { continue }

                        let titleObj = node["title"] as? [String: Any]
                        let romaji = titleObj?["romaji"] as? String ?? "Upcoming Sequel"
                        let english = titleObj?["english"] as? String
                        let native = titleObj?["native"] as? String
                        let synonyms = node["synonyms"] as? [String] ?? []

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

                        let coverObj = node["coverImage"] as? [String: Any]
                        let cover = coverObj?["large"] as? String ?? ""

                        var airingFormatted: String? = nil
                        if let s = season?.capitalized, let y = seasonYear {
                            airingFormatted = "\(s) \(y)"
                        } else if let y = seasonYear {
                            airingFormatted = "\(y)"
                        }

                        let desc = MetadataHydrationService.stripHTMLTags(from: node["description"] as? String)

                        let alertItem = SequelAlertItem(
                            parentMalId: parentMalId,
                            parentTitle: parentTitle,
                            parentEnglishTitle: parentEnglish,
                            parentJapaneseTitle: parentNative,
                            sequelMalId: sequelMal,
                            sequelTitle: romaji,
                            sequelEnglishTitle: resolvedEnglish,
                            sequelJapaneseTitle: native,
                            sequelCoverImageURL: cover,
                            sequelStatus: status,
                            airingSeasonYear: airingFormatted,
                            synopsis: desc
                        )
                        items.append(alertItem)
                    }
                }
            }

            return items
        } catch {
            return []
        }
    }
}
