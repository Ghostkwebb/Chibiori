import Foundation

public actor DubbedLanguageService {
    public static let shared = DubbedLanguageService()

    private var memoryCache: [Int: [DubbedLanguage]] = [:]
    private var isMyDubListInitialized = false
    private var regionalDubIndex: [String: Set<Int>] = [:] // lowercase language -> Set of malIDs

    private let allDatasetLanguages = [
        "english", "spanish", "french", "german", "italian", "portuguese",
        "russian", "hindi", "chinese", "korean", "arabic", "tagalog",
        "thai", "polish", "indonesian", "turkish", "vietnamese", "catalan",
        "dutch", "swedish", "norwegian", "danish", "finnish", "hungarian", "hebrew"
    ]

    private let cacheDirectory: URL

    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Chibiori/dubs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir

        var initialIndex: [String: Set<Int>] = [:]
        for lang in allDatasetLanguages {
            if let data = DubbedLanguageService.findLocalData(for: lang, cacheDirectory: dir),
               let set = DubbedLanguageService.parseMyDubListJson(data) {
                initialIndex[lang.lowercased()] = set
            }
        }
        self.regionalDubIndex = initialIndex
    }

    /// Checks if a MAL ID is verified to have an English dub in the dataset
    public func hasVerifiedEnglishDub(malId: Int) -> Bool {
        if let englishSet = regionalDubIndex["english"] {
            return englishSet.contains(malId)
        }
        return false
    }

    /// Fetches all dubbed and original audio languages for a given MyAnimeList ID
    public func fetchDubbedLanguages(malId: Int, forceRefresh: Bool = false) async -> [DubbedLanguage] {
        if !forceRefresh, let cached = memoryCache[malId] {
            return cached
        }

        // Ensure all language datasets are loaded/updated
        await ensureRegionalDatasetsLoaded()

        var discoveredLanguages = Set<String>()
        var originCountry: String? = "JP"

        // 1. Cross-reference datasets (instant offline lookup for 25 languages including English)
        for (langKey, idSet) in regionalDubIndex {
            if idSet.contains(malId) {
                discoveredLanguages.insert(langKey.capitalized)
            }
        }

        // 2. Query AniList GraphQL for country of origin and additional voice actor tracks
        // Always run on forceRefresh or if we want to discover voice actors/native country
        if let aniData = await fetchAniListVoiceLanguages(malId: malId) {
            if let c = aniData.country {
                originCountry = c
            }
            for lang in aniData.languages {
                discoveredLanguages.insert(lang)
            }
        }

        // 3. Resolve native language based on country of origin
        let isChineseNative = (originCountry == "CN")
        let isKoreanNative = (originCountry == "KR")
        let isJapaneseNative = !isChineseNative && !isKoreanNative

        var resolvedList: [DubbedLanguage] = []
        var seenCodes = Set<String>()

        // Always ensure original production audio is included
        if isJapaneseNative {
            resolvedList.append(DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵"))
            seenCodes.insert("JP")
        } else if isChineseNative {
            resolvedList.append(DubbedLanguage(code: "ZH", name: "Chinese", nativeName: "中文", isNativeAudio: true, flag: "🇨🇳"))
            seenCodes.insert("ZH")
        } else if isKoreanNative {
            resolvedList.append(DubbedLanguage(code: "KO", name: "Korean", nativeName: "한국어", isNativeAudio: true, flag: "🇰🇷"))
            seenCodes.insert("KO")
        }

        // Add discovered dub languages
        for raw in discoveredLanguages {
            let lang = DubbedLanguage.resolve(from: raw)
            if !seenCodes.contains(lang.code) {
                seenCodes.insert(lang.code)
                resolvedList.append(lang)
            }
        }

        let sorted = resolvedList.sorted {
            if $0.sortPriority != $1.sortPriority {
                return $0.sortPriority < $1.sortPriority
            }
            return $0.name < $1.name
        }

        if !sorted.isEmpty {
            memoryCache[malId] = sorted
        }
        return sorted
    }

    /// Batch fetch for multiple anime IDs
    public func fetchDubbedLanguagesBatch(malIds: [Int]) async -> [Int: [DubbedLanguage]] {
        var results: [Int: [DubbedLanguage]] = [:]
        for id in malIds {
            results[id] = await fetchDubbedLanguages(malId: id)
        }
        return results
    }

    // MARK: - AniList GraphQL Voice Actors Query
    private struct AniListVoiceResult {
        let country: String?
        let languages: [String]
    }

    private func fetchAniListVoiceLanguages(malId: Int) async -> AniListVoiceResult? {
        let gql = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: ANIME) {
            countryOfOrigin
            characters(sort: [ROLE, RELEVANCE, ID], page: 1, perPage: 25) {
              edges {
                node { id }
                voiceActors {
                  id
                  languageV2
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
        request.setValue("Chibiori-Desktop/1.0", forHTTPHeaderField: "User-Agent")

        let bodyDict: [String: Any] = ["query": gql, "variables": ["idMal": malId]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyDict) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 429 {
                // Rate limited - back off silently
                return nil
            }
            guard http.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let media = dataObj["Media"] as? [String: Any] else {
                return nil
            }

            let country = media["countryOfOrigin"] as? String
            var langs: [String] = []

            if let characters = media["characters"] as? [String: Any],
               let edges = characters["edges"] as? [[String: Any]] {
                for edge in edges {
                    if let actors = edge["voiceActors"] as? [[String: Any]] {
                        for actor in actors {
                            if let l = actor["languageV2"] as? String, !l.isEmpty {
                                langs.append(l)
                            }
                        }
                    }
                }
            }

            return AniListVoiceResult(country: country, languages: Array(Set(langs)))
        } catch {
            return nil
        }
    }

    // MARK: - MyDubList Datasets & Local File Fallbacks
    private func ensureRegionalDatasetsLoaded() async {
        guard !isMyDubListInitialized else { return }
        isMyDubListInitialized = true

        await withTaskGroup(of: (String, Set<Int>).self) { group in
            for lang in allDatasetLanguages {
                group.addTask {
                    let set = await self.loadMyDubListLanguageFile(language: lang)
                    return (lang.lowercased(), set)
                }
            }

            for await (langKey, idSet) in group {
                if !idSet.isEmpty {
                    self.regionalDubIndex[langKey] = idSet
                }
            }
        }
    }

    private nonisolated static func findLocalData(for language: String, cacheDirectory: URL) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent("dubbed_\(language).json")
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }

        // Check bundled Resources in app
        if let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("dubs/dubbed_\(language).json"),
           let data = try? Data(contentsOf: bundledURL) {
            return data
        }

        // Check workspace relative Resources
        let workspaceURL = URL(fileURLWithPath: "Resources/dubs/dubbed_\(language).json")
        if let data = try? Data(contentsOf: workspaceURL) {
            return data
        }

        return nil
    }

    private func loadMyDubListLanguageFile(language: String) async -> Set<Int> {
        let fileURL = cacheDirectory.appendingPathComponent("dubbed_\(language).json")

        // 1. Check if user cache file is fresh (within 7 days)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < 604_800,
           let localData = try? Data(contentsOf: fileURL),
           let set = DubbedLanguageService.parseMyDubListJson(localData) {
            return set
        }

        // 2. Check bundled asset if available and cache file doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path),
           let localData = DubbedLanguageService.findLocalData(for: language, cacheDirectory: cacheDirectory),
           let set = DubbedLanguageService.parseMyDubListJson(localData) {
            try? localData.write(to: fileURL)
            return set
        }

        // 3. Fetch fresh from MyDubList GitHub repo (open dataset under CC BY 4.0)
        let urlString = "https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/confidence/low/dubbed_\(language).json"
        guard let url = URL(string: urlString) else {
            if let localData = DubbedLanguageService.findLocalData(for: language, cacheDirectory: cacheDirectory),
               let set = DubbedLanguageService.parseMyDubListJson(localData) {
                return set
            }
            return []
        }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.setValue("Chibiori-Desktop/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // If network fails, try existing local data
            if let localData = DubbedLanguageService.findLocalData(for: language, cacheDirectory: cacheDirectory),
               let set = DubbedLanguageService.parseMyDubListJson(localData) {
                return set
            }
            return []
        }

        try? data.write(to: fileURL)
        return DubbedLanguageService.parseMyDubListJson(data) ?? []
    }

    private nonisolated static func parseMyDubListJson(_ data: Data) -> Set<Int>? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dubbedArray = json["dubbed"] as? [Int] else {
            return nil
        }
        return Set(dubbedArray)
    }
}
