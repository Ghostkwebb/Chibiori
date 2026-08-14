import Foundation
import SwiftData
import Observation

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
}

@Observable
@MainActor
public final class SequelAlertService {
    public static let shared = SequelAlertService()

    public var alerts: [SequelAlertItem] = []
    public var isScanning: Bool = false
    public var lastScannedDate: Date? = nil

    private init() {}

    /// Scans completed anime list to detect newly announced or upcoming sequels/seasons
    public func scanForSequels(completedAnime: [TrackedAnime], existingTrackedIDs: Set<Int>) async {
        guard !isScanning else { return }
        isScanning = true

        var discoveredAlerts: [SequelAlertItem] = []

        // Query in batches to respect rate limits
        for anime in completedAnime.prefix(40) {
            let malID = anime.malID
            if let result = await queryRelations(
                for: malID,
                parentTitle: anime.title,
                parentEnglishTitle: anime.englishTitle,
                parentJapaneseTitle: anime.japaneseTitle
            ) {
                for item in result {
                    // Check if the sequel is NOT already in the user's library
                    if !existingTrackedIDs.contains(item.sequelMalId) {
                        discoveredAlerts.append(item)
                    }
                }
            }
        }

        self.alerts = discoveredAlerts
        self.lastScannedDate = Date()
        self.isScanning = false
    }

    private func queryRelations(
        for malID: Int,
        parentTitle: String,
        parentEnglishTitle: String?,
        parentJapaneseTitle: String?
    ) async -> [SequelAlertItem]? {
        let gql = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: ANIME) {
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
        """

        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["idMal": malID]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let mediaObj = dataObj["Media"] as? [String: Any],
                  let relObj = mediaObj["relations"] as? [String: Any],
                  let edges = relObj["edges"] as? [[String: Any]] else {
                return nil
            }

            var items: [SequelAlertItem] = []

            for edge in edges {
                let relType = edge["relationType"] as? String ?? ""
                guard relType == "SEQUEL" || relType == "SIDE_STORY" else { continue }

                guard let node = edge["node"] as? [String: Any] else { continue }
                let status = node["status"] as? String ?? ""
                let season = node["season"] as? String
                let seasonYear = node["seasonYear"] as? Int

                // Check if upcoming or recent sequel
                let isUpcoming = (status == "NOT_YET_RELEASED" || status == "RELEASING")
                let isFutureYear = (seasonYear ?? 0) >= 2025

                if isUpcoming || isFutureYear {
                    let sequelMal = node["idMal"] as? Int ?? node["id"] as? Int ?? 0
                    guard sequelMal > 0, sequelMal != malID else { continue }

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
                        parentMalId: malID,
                        parentTitle: parentTitle,
                        parentEnglishTitle: parentEnglishTitle,
                        parentJapaneseTitle: parentJapaneseTitle,
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

            return items
        } catch {
            return nil
        }
    }
}
