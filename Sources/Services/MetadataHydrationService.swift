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

    /// Hydrates all TrackedAnime models that have missing cover images or synopses
    public func hydrateMissingMetadata(context: ModelContext) async {
        guard !isHydrating else { return }

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        guard let allAnimes = try? context.fetch(fetchDescriptor) else { return }

        let missingAnimes = allAnimes.filter { $0.coverImageRemoteURL.isEmpty || $0.synopsis.isEmpty }
        guard !missingAnimes.isEmpty else { return }

        isHydrating = true
        currentProgress = 0.0
        statusMessage = "Fetching cover images and metadata for \(missingAnimes.count) anime..."

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
                    if anime.coverImageRemoteURL.isEmpty, let cover = meta.coverURL, !cover.isEmpty {
                        anime.coverImageRemoteURL = cover
                    }
                    if anime.synopsis.isEmpty, let syn = meta.synopsis, !syn.isEmpty {
                        anime.synopsis = syn
                    }
                    if anime.japaneseTitle == nil, let jp = meta.japaneseTitle {
                        anime.japaneseTitle = jp
                    }
                    if anime.malScore == nil, let score = meta.score {
                        anime.malScore = score
                    }
                    if anime.seasonYear == nil, let year = meta.seasonYear {
                        anime.seasonYear = year
                    }
                    if anime.genres.isEmpty, !meta.genres.isEmpty {
                        anime.genres = meta.genres
                    }
                }
            }

            try? context.save()

            processed += chunk.count
            currentProgress = Double(processed) / Double(missingAnimes.count)
            statusMessage = "Fetched \(processed) of \(missingAnimes.count) anime posters..."

            if index < chunks.count - 1 {
                // Gentle delay between batches to respect rate limits
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        statusMessage = "All \(missingAnimes.count) anime covers updated successfully!"
        isHydrating = false

        // Clear status message after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !self.isHydrating {
                self.statusMessage = nil
            }
        }
    }

    private struct FetchedMetadata {
        let malID: Int
        let title: String?
        let japaneseTitle: String?
        let coverURL: String?
        let synopsis: String?
        let score: Double?
        let seasonYear: String?
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
              averageScore
              season
              seasonYear
              status
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

                let desc = (item["description"] as? String)?
                    .replacingOccurrences(of: "<br>", with: "\n")
                    .replacingOccurrences(of: "<i>", with: "")
                    .replacingOccurrences(of: "</i>", with: "")
                    .replacingOccurrences(of: "<b>", with: "")
                    .replacingOccurrences(of: "</b>", with: "")

                let avgScore = (item["averageScore"] as? Double ?? Double(item["averageScore"] as? Int ?? 0)) / 10.0
                let season = item["season"] as? String
                let year = item["seasonYear"] as? Int
                var seasonYearFormatted: String? = nil
                if let s = season?.capitalized, let y = year {
                    seasonYearFormatted = "\(s) \(y)"
                } else if let y = year {
                    seasonYearFormatted = "\(y)"
                }

                let genres = item["genres"] as? [String] ?? []

                let meta = FetchedMetadata(
                    malID: idMal,
                    title: romaji,
                    japaneseTitle: native,
                    coverURL: coverLarge,
                    synopsis: desc,
                    score: avgScore > 0 ? avgScore : nil,
                    seasonYear: seasonYearFormatted,
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
