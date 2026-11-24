import Foundation

/// Resolves and caches dubbed audio languages using bundled/local MyDubList datasets and AniList voice actor metadata.
public actor DubbedLanguageService {
    public static let shared = DubbedLanguageService()

    private static let maxMemoryCacheEntries = 300
    private static let datasetFreshnessInterval: TimeInterval = 604_800 // 7 days

    private var memoryCache: [Int: [DubbedLanguage]] = [:]
    private var memoryCacheOrder: [Int] = []
    private var isLocalDatasetsLoaded = false
    private var hasStartedBackgroundRefresh = false
    private var regionalDubIndex: [String: Set<Int>] = [:] // lowercase language -> Set of malIDs

    private let allDatasetLanguages = [
        "english", "spanish", "french", "german", "italian", "portuguese",
        "russian", "hindi", "chinese", "korean", "arabic", "tagalog",
        "thai", "polish", "indonesian", "turkish", "vietnamese", "catalan",
        "dutch", "swedish", "norwegian", "danish", "finnish", "hungarian", "hebrew"
    ]

    private let cacheDirectory: URL
    private let aniList: AniListClient
    private let session: URLSession

    public init(
        cacheDirectory: URL? = nil,
        aniList: AniListClient = .shared,
        session: URLSession = .shared
    ) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            self.cacheDirectory = paths[0].appendingPathComponent("Chibiori/dubs", isDirectory: true)
        }
        self.aniList = aniList
        self.session = session
    }

    /// Checks if a MAL ID is verified to have an English dub in the loaded datasets.
    public func hasVerifiedEnglishDub(malId: Int) -> Bool {
        ensureLocalDatasetsLoaded()
        return regionalDubIndex["english"]?.contains(malId) ?? false
    }

    /// Returns a snapshot of all MAL IDs verified to have an English dub.
    public func verifiedEnglishDubIDs() -> Set<Int> {
        ensureLocalDatasetsLoaded()
        return regionalDubIndex["english"] ?? []
    }

    /// Fast offline resolution using local MyDubList datasets without network queries.
    public func offlineDubbedLanguages(malId: Int) -> [DubbedLanguage] {
        ensureLocalDatasetsLoaded()

        var discoveredLanguages = Set<String>()
        for (langKey, idSet) in regionalDubIndex where idSet.contains(malId) {
            discoveredLanguages.insert(langKey.capitalized)
        }
        var resolvedList: [DubbedLanguage] = [
            DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵")
        ]
        for raw in discoveredLanguages {
            let lang = DubbedLanguage.resolve(from: raw)
            if lang.code != "JP" && !resolvedList.contains(where: { $0.code == lang.code }) {
                resolvedList.append(lang)
            }
        }
        return resolvedList
    }

    /// Fetches all dubbed and original audio languages for a given MyAnimeList ID.
    public func fetchDubbedLanguages(malId: Int, forceRefresh: Bool = false) async -> [DubbedLanguage] {
        if !forceRefresh, let cached = memoryCache[malId] {
            return cached
        }

        ensureLocalDatasetsLoaded()
        scheduleBackgroundDatasetRefreshIfNeeded()

        var discoveredLanguages = Set<String>()
        var originCountry: String? = "JP"

        for (langKey, idSet) in regionalDubIndex where idSet.contains(malId) {
            discoveredLanguages.insert(langKey.capitalized)
        }

        if let aniData = await aniList.fetchVoiceLanguages(malId: malId) {
            if let country = aniData.country {
                originCountry = country
            }
            for lang in aniData.languages {
                discoveredLanguages.insert(lang)
            }
        }

        let isChineseNative = (originCountry == "CN")
        let isKoreanNative = (originCountry == "KR")
        let isJapaneseNative = !isChineseNative && !isKoreanNative

        var resolvedList: [DubbedLanguage] = []
        var seenCodes = Set<String>()

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
            storeInMemoryCache(sorted, for: malId)
        }
        return sorted
    }

    /// Batch fetch for multiple anime IDs.
    public func fetchDubbedLanguagesBatch(malIds: [Int]) async -> [Int: [DubbedLanguage]] {
        var results: [Int: [DubbedLanguage]] = [:]
        for id in malIds {
            results[id] = await fetchDubbedLanguages(malId: id)
        }
        return results
    }

    // MARK: - Cache & Local Dataset Loading

    private func storeInMemoryCache(_ value: [DubbedLanguage], for malId: Int) {
        if memoryCache[malId] == nil {
            memoryCacheOrder.append(malId)
        }
        memoryCache[malId] = value
        if memoryCacheOrder.count > Self.maxMemoryCacheEntries {
            let oldest = memoryCacheOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }

    private func ensureLocalDatasetsLoaded() {
        guard !isLocalDatasetsLoaded else { return }
        isLocalDatasetsLoaded = true

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        var loadedIndex: [String: Set<Int>] = [:]
        for lang in allDatasetLanguages {
            if let data = Self.findLocalData(for: lang, cacheDirectory: cacheDirectory),
               let set = Self.parseMyDubListJson(data) {
                loadedIndex[lang.lowercased()] = set
            }
        }
        self.regionalDubIndex = loadedIndex
    }

    private func scheduleBackgroundDatasetRefreshIfNeeded() {
        guard !hasStartedBackgroundRefresh else { return }
        hasStartedBackgroundRefresh = true

        let staleLanguages = allDatasetLanguages.filter { language in
            let fileURL = cacheDirectory.appendingPathComponent("dubbed_\(language).json")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return true
            }
            return Date().timeIntervalSince(modDate) >= Self.datasetFreshnessInterval
        }

        guard !staleLanguages.isEmpty else { return }

        let dir = cacheDirectory
        let urlSession = session
        Task.detached(priority: .utility) { [weak self] in
            var refreshed: [String: Set<Int>] = [:]
            var nextIndex = 0
            let maxConcurrent = 4

            await withTaskGroup(of: (String, Set<Int>?).self) { group in
                let initialCount = min(maxConcurrent, staleLanguages.count)
                while nextIndex < initialCount {
                    let lang = staleLanguages[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let set = await Self.refreshRemoteDataset(language: lang, cacheDirectory: dir, session: urlSession)
                        return (lang.lowercased(), set)
                    }
                }

                for await (langKey, maybeSet) in group {
                    if let maybeSet, !maybeSet.isEmpty {
                        refreshed[langKey] = maybeSet
                    }
                    if nextIndex < staleLanguages.count {
                        let lang = staleLanguages[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            let set = await Self.refreshRemoteDataset(language: lang, cacheDirectory: dir, session: urlSession)
                            return (lang.lowercased(), set)
                        }
                    }
                }
            }

            if !refreshed.isEmpty, let self {
                await self.mergeRefreshedDatasets(refreshed)
            }
        }
    }

    private func mergeRefreshedDatasets(_ refreshed: [String: Set<Int>]) {
        for (langKey, idSet) in refreshed {
            regionalDubIndex[langKey] = idSet
        }
    }

    private nonisolated static func findLocalData(for language: String, cacheDirectory: URL) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent("dubbed_\(language).json")
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }

        if let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("dubs/dubbed_\(language).json"),
           let data = try? Data(contentsOf: bundledURL) {
            return data
        }

        let workspaceURL = URL(fileURLWithPath: "Resources/dubs/dubbed_\(language).json")
        if let data = try? Data(contentsOf: workspaceURL) {
            return data
        }

        return nil
    }

    private nonisolated static func refreshRemoteDataset(
        language: String,
        cacheDirectory: URL,
        session: URLSession
    ) async -> Set<Int>? {
        let fileURL = cacheDirectory.appendingPathComponent("dubbed_\(language).json")
        let urlString = "https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/confidence/low/dubbed_\(language).json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.setValue("Chibiori-Desktop/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let set = parseMyDubListJson(data) else {
            return nil
        }

        try? data.write(to: fileURL, options: .atomic)
        return set
    }

    private nonisolated static func parseMyDubListJson(_ data: Data) -> Set<Int>? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dubbedArray = json["dubbed"] as? [Int] else {
            return nil
        }
        return Set(dubbedArray)
    }
}
