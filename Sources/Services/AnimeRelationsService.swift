import Foundation
import Observation

@Observable
@MainActor
public final class AnimeRelationsService {
    public static let shared = AnimeRelationsService()

    private var cache: [Int: [RelatedAnimeItem]] = [:]
    private var activeTasks: [Int: Task<[RelatedAnimeItem], Never>] = [:]

    private init() {}

    /// Fetches all related anime seasons (prequels, sequels, parent story, side stories) for the given MAL ID.
    /// Returns only anime relations (ignoring manga/light novel adaptations).
    public func fetchRelations(for malID: Int) async -> [RelatedAnimeItem] {
        guard malID > 0 else { return [] }

        if let cached = cache[malID] {
            return cached
        }

        // Deduplicate in-flight network requests for the same MAL ID
        if let existingTask = activeTasks[malID] {
            return await existingTask.value
        }

        let task = Task<[RelatedAnimeItem], Never> { @MainActor in
            let results = await self.performAniListRelationsQuery(for: malID)
            self.cache[malID] = results
            self.activeTasks.removeValue(forKey: malID)
            return results
        }

        activeTasks[malID] = task
        return await task.value
    }

    private func performAniListRelationsQuery(for malID: Int) async -> [RelatedAnimeItem] {
        let gql = """
        query ($id: Int) {
          Media(idMal: $id, type: ANIME) {
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
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["id": malID]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let media = dataObj["Media"] as? [String: Any],
                  let relObj = media["relations"] as? [String: Any],
                  let edges = relObj["edges"] as? [[String: Any]] else {
                return []
            }

            var items: [RelatedAnimeItem] = []
            var seenMalIDs = Set<Int>()

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

                guard let relMalId = node["idMal"] as? Int, relMalId > 0, relMalId != malID else {
                    continue
                }

                if seenMalIDs.contains(relMalId) {
                    continue
                }
                seenMalIDs.insert(relMalId)

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
                    malID: relMalId,
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
        } catch {
            return []
        }
    }

    /// Preloads or injects relations into cache (useful for testing or previews)
    public func setCachedRelations(_ relations: [RelatedAnimeItem], for malID: Int) {
        cache[malID] = relations
    }

    /// Clears the in-memory cache
    public func clearCache() {
        cache.removeAll()
    }
}
