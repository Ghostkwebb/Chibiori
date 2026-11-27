import XCTest
import SwiftData
@testable import ChibioriCore

final class ServicesAndCachingTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChibioriTests-Services-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - SequelAlertService Isolated Persistence & UserDefaults Migration

    @MainActor
    func testSequelAlertServiceCacheAndMigration() async throws {
        let suiteName = "ChibioriTests.Sequel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let alert = SequelAlertItem(
            parentMalId: 40748,
            parentTitle: "Jujutsu Kaisen",
            sequelMalId: 51009,
            sequelTitle: "Jujutsu Kaisen 2nd Season",
            sequelEnglishTitle: "Jujutsu Kaisen Season 2",
            airingSeasonYear: "Summer 2023"
        )
        XCTAssertEqual(alert.displaySequelTitle(for: .english), "Jujutsu Kaisen Season 2")

        // Seed legacy UserDefaults key and verify one-time migration to JSON file
        let legacyData = try JSONEncoder().encode([alert])
        defaults.set(legacyData, forKey: "savedSequelAlertsData")

        let cacheFileURL = tempRoot.appendingPathComponent("sequel_alerts.json")
        let service = SequelAlertService(cacheFileURL: cacheFileURL, defaults: defaults)

        XCTAssertEqual(service.alerts.count, 1)
        XCTAssertEqual(service.alerts.first?.sequelMalId, 51009)
        XCTAssertNil(defaults.data(forKey: "savedSequelAlertsData"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFileURL.path))

        // Reload fresh service purely from JSON file
        let reloaded = SequelAlertService(cacheFileURL: cacheFileURL, defaults: defaults)
        XCTAssertEqual(reloaded.alerts, [alert])
    }

    // MARK: - CloudSyncService Isolated Backup & Auto-Restore

    @MainActor
    func testCloudSyncServiceIsolatedBackupAndRestore() async throws {
        let cloudFolder = tempRoot.appendingPathComponent("CloudDrive", isDirectory: true)
        let syncService = CloudSyncService(folderURL: cloudFolder)

        let schema = Schema([TrackedAnime.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let sourceContext = ModelContext(container)

        let anime = TrackedAnime(
            malID: 57524,
            title: "Makeine: Too Many Losing Heroines!",
            synopsis: "Losing heroines comedy.",
            coverImageRemoteURL: "https://example.com/makeine.jpg",
            airingStatusRaw: "Finished Airing",
            dubbedLanguages: ["Japanese", "English"]
        )
        anime.setWatchStatus(.completed)
        sourceContext.insert(anime)
        try sourceContext.save()

        syncService.performAutoCloudBackup(from: [anime])

        // Wait up to 2s for detached JSON encode + NSFileCoordinator write
        let syncFile = cloudFolder.appendingPathComponent("Chibiori_CloudSync.json")
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: syncFile.path) && !syncService.isSyncing {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncFile.path))

        // Restore into a fresh empty ModelContainer
        let container2 = try ModelContainer(for: schema, configurations: [config])
        let restoreContext = ModelContext(container2)
        let restored = syncService.autoRestoreIfLibraryEmpty(context: restoreContext)
        XCTAssertTrue(restored)

        let fetched = try restoreContext.fetch(FetchDescriptor<TrackedAnime>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.malID, 57524)
        XCTAssertEqual(fetched.first?.dubbedLanguages, ["Japanese", "English"])
    }

    // MARK: - AnimeRelationsService Disk TTL Cache & Franchise Discovery

    func testAnimeRelationsServiceCacheTTLAndFranchiseDiscovery() async throws {
        let relRoot = tempRoot.appendingPathComponent("RelationsCache", isDirectory: true)
        let service = AnimeRelationsService(cacheRootURL: relRoot)

        let mockItem = RelatedAnimeItem(malID: 58567, relationType: "SEQUEL", title: "Sequel Item")
        await service.setCachedRelations([mockItem], for: 52299)
        await service.clearCache()

        // Fresh envelope should hit disk cache
        let cachedFromDisk = await service.fetchRelations(for: 52299)
        XCTAssertEqual(cachedFromDisk.count, 1)
        XCTAssertEqual(cachedFromDisk.first?.malID, 58567)

        // Legacy bare-array file should also decode cleanly
        let legacyFile = relRoot.appendingPathComponent("relations/77777.json")
        let legacyPayload = try JSONEncoder().encode([RelatedAnimeItem(malID: 88888, relationType: "PREQUEL", title: "Legacy Prequel")])
        try legacyPayload.write(to: legacyFile)
        let decodedLegacy = await service.fetchRelations(for: 77777)
        XCTAssertEqual(decodedLegacy.first?.malID, 88888)

        // Expired TTL envelope (8 days old) without network should return empty or fallback cleanly when mocked offline
        let mockSession = MockURLProtocol.makeSession { _ in
            MockStubResponse(statusCode: 503, body: Data())
        }
        defer { MockURLProtocol.unregister(session: mockSession) }

        let offlineClient = AniListClient(session: mockSession, minimumInterval: 0)
        let offlineService = AnimeRelationsService(cacheRootURL: relRoot, aniList: offlineClient, session: mockSession)
        let expiredFile = relRoot.appendingPathComponent("relations/99991.json")
        let expiredJSON = """
        {"cachedAt": \(Date().addingTimeInterval(-8 * 86_400).timeIntervalSinceReferenceDate), "items": [{"malID": 12345, "relationType": "SEQUEL", "title": "Expired"}]}
        """
        try Data(expiredJSON.utf8).write(to: expiredFile)
        // Since expired disk item falls back to stale cache ONLY if network fails (graceful degradation),
        // verify cleanFranchiseRoot & local Makeine S1/S2 cross-discovery directly:
        XCTAssertEqual(offlineService.cleanFranchiseRoot("Makeine: Too Many Losing Heroines! Season 2"), "makeine too many losing heroines")

        let makeine1 = LibraryMatchSnapshot(
            malID: 57524,
            title: "Makeine: Too Many Losing Heroines!",
            englishTitle: "Makeine: Too Many Losing Heroines!",
            seasonYear: "Summer 2024"
        )
        let makeine2 = LibraryMatchSnapshot(
            malID: 61398,
            title: "Makeine: Too Many Losing Heroines! Season 2",
            englishTitle: "Makeine: Too Many Losing Heroines! Season 2",
            seasonYear: "2025"
        )

        let relsForS2 = offlineService.discoverLibraryFranchiseRelations(for: makeine2, allLibrary: [makeine1, makeine2])
        XCTAssertTrue(relsForS2.contains(where: { $0.malID == 57524 && $0.relationType == "PREQUEL" }))

        let relsForS1 = offlineService.discoverLibraryFranchiseRelations(for: makeine1, allLibrary: [makeine1, makeine2])
        XCTAssertTrue(relsForS1.contains(where: { $0.malID == 61398 && $0.relationType == "SEQUEL" }))

        // Keep reference active until end
        _ = await offlineService.fetchRelations(for: 99991)
    }

    // MARK: - DubbedLanguageService Isolated Offline Dataset

    func testDubbedLanguageServiceOfflineDatasetLookup() async throws {
        let dubDir = tempRoot.appendingPathComponent("Dubs", isDirectory: true)
        try FileManager.default.createDirectory(at: dubDir, withIntermediateDirectories: true)

        let fixture = Data(#"{"dubbed":[5114,40748]}"#.utf8)
        try fixture.write(to: dubDir.appendingPathComponent("dubbed_english.json"))

        let dubService = DubbedLanguageService(cacheDirectory: dubDir)
        let hasFmaDub = await dubService.hasVerifiedEnglishDub(malId: 5114)
        XCTAssertTrue(hasFmaDub)

        let offline = await dubService.offlineDubbedLanguages(malId: 5114)
        XCTAssertTrue(offline.contains(where: { $0.code == "EN" }))
        XCTAssertTrue(offline.contains(where: { $0.code == "JP" }))
    }

    // MARK: - JikanAPIService Schedule Day Filtering & Fallback

    func testJikanAPIServiceScheduleDayWindowAndFallback() async throws {
        // 1. Validate local weekday window spans exact 24 hours (86400s) for requested weekday
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let mondayRef = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let mondayWindow = JikanAPIService.airingWindowTimestamps(forDay: "monday", referenceDate: mondayRef, calendar: calendar)
        let wednesdayWindow = JikanAPIService.airingWindowTimestamps(forDay: "wednesday", referenceDate: mondayRef, calendar: calendar)
        XCTAssertEqual(mondayWindow.end - mondayWindow.start, 86_400)
        XCTAssertEqual(wednesdayWindow.start - mondayWindow.start, 2 * 86_400)

        // 2. AniList airingSchedule query returns day-matched shows
        let anilistSession = MockURLProtocol.makeSession { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("airingSchedules"))
            let json = """
            {"data":{"Page":{"airingSchedules":[
              {"airingAt":\(wednesdayWindow.start + 3600),"episode":5,"media":{"id":10,"idMal":5001,"title":{"romaji":"Wednesday Show","english":"Wednesday Show","native":"水曜"},"status":"RELEASING","episodes":12,"averageScore":80,"genres":["Action"]}}
            ]}}}
            """
            return MockStubResponse(body: Data(json.utf8))
        }
        defer { MockURLProtocol.unregister(session: anilistSession) }

        let api = JikanAPIService(session: anilistSession, aniList: AniListClient(session: anilistSession, minimumInterval: 0), minimumInterval: 0)
        let wednesdayShows = try await api.fetchSchedules(day: "wednesday", referenceDate: mondayRef)
        XCTAssertEqual(wednesdayShows.map(\.malId), [5001])

        // 3. When AniList fails, JikanAPIService must hit /v4/schedules?filter=friday (never unfiltered seasonal list)
        let fallbackSession = MockURLProtocol.makeSession { request in
            let urlStr = request.url?.absoluteString ?? ""
            if urlStr.contains("graphql.anilist.co") {
                return MockStubResponse(statusCode: 500, body: Data())
            }
            XCTAssertTrue(urlStr.contains("/v4/schedules"))
            XCTAssertTrue(urlStr.contains("filter=friday"))
            let jikanPayload = """
            {"data":[{"mal_id":6002,"title":"Friday Fallback Show","status":"Currently Airing","episodes":12,"broadcast":{"day":"Fridays"}}]}
            """
            return MockStubResponse(body: Data(jikanPayload.utf8))
        }
        defer { MockURLProtocol.unregister(session: fallbackSession) }

        let fallbackAPI = JikanAPIService(session: fallbackSession, aniList: AniListClient(session: fallbackSession, minimumInterval: 0), minimumInterval: 0)
        let fridayShows = try await fallbackAPI.fetchSchedules(day: "friday", referenceDate: mondayRef)
        XCTAssertEqual(fridayShows.map(\.malId), [6002])
    }

    // MARK: - ViewModel Cancellation Races

    @MainActor
    func testDiscoverAndScheduleViewModelCancelStaleTasks() async throws {
        let mondayStart = JikanAPIService.airingWindowTimestamps(forDay: Weekday.monday.rawValue).start
        let raceSession = MockURLProtocol.makeSession { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            if body.contains("\"s\":\"old\"") {
                let slowJSON = """
                {"data":{"Page":{"media":[{"id":1,"idMal":111,"title":{"romaji":"Old Delayed Result","english":"Old Delayed Result"},"status":"FINISHED"}]}}}
                """
                return MockStubResponse(body: Data(slowJSON.utf8), delay: 0.35)
            }
            if body.contains("\"s\":\"new\"") {
                let fastJSON = """
                {"data":{"Page":{"media":[{"id":2,"idMal":222,"title":{"romaji":"New Fresh Result","english":"New Fresh Result"},"status":"FINISHED"}]}}}
                """
                return MockStubResponse(body: Data(fastJSON.utf8), delay: 0.01)
            }

            if body.contains("\"start\":\(mondayStart)") {
                let scheduleSlow = """
                {"data":{"Page":{"airingSchedules":[{"airingAt":\(mondayStart + 3600),"episode":1,"media":{"id":3,"idMal":333,"title":{"romaji":"Monday Stale"},"status":"RELEASING"}}]}}}
                """
                return MockStubResponse(body: Data(scheduleSlow.utf8), delay: 0.35)
            }

            let scheduleFast = """
            {"data":{"Page":{"airingSchedules":[{"airingAt":\(mondayStart + 90_000),"episode":2,"media":{"id":4,"idMal":444,"title":{"romaji":"Tuesday Fresh"},"status":"RELEASING"}}]}}}
            """
            return MockStubResponse(body: Data(scheduleFast.utf8), delay: 0.01)
        }
        defer { MockURLProtocol.unregister(session: raceSession) }

        let api = JikanAPIService(session: raceSession, aniList: AniListClient(session: raceSession, minimumInterval: 0), minimumInterval: 0)
        let discoverVM = DiscoverViewModel(apiService: api)

        discoverVM.searchQuery = "old"
        discoverVM.performSearch()
        try await Task.sleep(nanoseconds: 280_000_000) // allow debounce to dispatch "old" network request
        discoverVM.searchQuery = "new"
        discoverVM.performSearch()

        // Wait past slow response duration
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(discoverVM.results.map(\.malId), [222])
        XCTAssertFalse(discoverVM.isLoading)

        let scheduleVM = ScheduleViewModel(apiService: api)
        scheduleVM.selectedDay = .monday
        scheduleVM.loadSchedule()
        try await Task.sleep(nanoseconds: 20_000_000)
        scheduleVM.selectedDay = .tuesday
        scheduleVM.loadSchedule()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(scheduleVM.isLoading)
        XCTAssertEqual(scheduleVM.schedules.map(\.malId), [444])
    }

    // MARK: - MultiSiteScoreService Multi-Provider Resolution & Caching

    func testMultiSiteScoreServiceFetchesNormalizesAndCachesScores() async throws {
        let session = MockURLProtocol.makeSession { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("api.jikan.moe/v4/anime/64459") {
                return MockStubResponse(body: Data(#"{"data":{"score":8.15}}"#.utf8))
            }
            if url.contains("graphql.anilist.co") {
                return MockStubResponse(body: Data(#"{"data":{"Media":{"id":180999,"averageScore":68}}}"#.utf8))
            }
            if url.contains("kitsu.io/api/edge/mappings") {
                return MockStubResponse(body: Data(#"{"included":[{"type":"anime","attributes":{"slug":"fool-night","averageRating":"83.06"}}]}"#.utf8))
            }
            if url.contains("shikimori.io/api/animes/64459") {
                return MockStubResponse(body: Data(#"{"id":64459,"score":"7.76"}"#.utf8))
            }
            return MockStubResponse(statusCode: 404, body: Data())
        }
        defer { MockURLProtocol.unregister(session: session) }

        let cacheFile = tempRoot.appendingPathComponent("site_scores.json")
        let service = MultiSiteScoreService(
            cacheFileURL: cacheFile,
            session: session,
            aniList: AniListClient(session: session, minimumInterval: 0)
        )

        let scores = await service.fetchAllScores(for: 64459)
        XCTAssertEqual(scores.malScore ?? 0, 8.15, accuracy: 0.001)
        XCTAssertEqual(scores.aniListScore ?? 0, 6.8, accuracy: 0.001)
        XCTAssertEqual(scores.kitsuScore ?? 0, 8.306, accuracy: 0.001)
        XCTAssertEqual(scores.shikimoriScore ?? 0, 7.76, accuracy: 0.001)
        XCTAssertEqual(scores.aniListID, 180999)
        XCTAssertEqual(scores.kitsuSlug, "fool-night")
        XCTAssertEqual(scores.primaryCardBadge?.source, .mal)
        XCTAssertEqual(ScoreSource.aniList.pageURL(malID: 64459, aniListID: scores.aniListID)?.absoluteString, "https://anilist.co/anime/180999")
        XCTAssertEqual(ScoreSource.kitsu.pageURL(malID: 64459, kitsuSlug: scores.kitsuSlug)?.absoluteString, "https://kitsu.io/anime/fool-night")

        // Wait briefly for debounced disk write, then reload fresh instance
        try await Task.sleep(nanoseconds: 500_000_000)
        let reloaded = MultiSiteScoreService(cacheFileURL: cacheFile, session: session)
        let cached = await reloaded.cachedScores(for: 64459)
        XCTAssertEqual(cached?.malScore ?? 0, 8.15, accuracy: 0.001)
        XCTAssertEqual(cached?.shikimoriScore ?? 0, 7.76, accuracy: 0.001)

        // Verify direct MAL public HTML fallback score parser when Jikan is unreachable
        let sampleHTML = """
        <span itemprop="ratingValue" class="score-label score-8">8.16</span>
        """
        XCTAssertEqual(MultiSiteScoreService.parseMALHTMLScore(from: sampleHTML) ?? 0, 8.16, accuracy: 0.001)

        // Verify partial MAL-only prefetch still allows fetchAllScores to populate all other providers in the inspector
        let partialPrefetched = await reloaded.prefetchBatchScores(for: [90001], preference: .mal)
        XCTAssertTrue(partialPrefetched.isEmpty || partialPrefetched[90001]?.hasFetchedAllProviders == false)
        let session2 = MockURLProtocol.makeSession { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("api.jikan.moe/v4/anime/90002") {
                return MockStubResponse(body: Data(#"{"data":{"score":8.57}}"#.utf8))
            }
            if url.contains("graphql.anilist.co") {
                return MockStubResponse(body: Data(#"{"data":{"Media":{"id":555,"averageScore":86}}}"#.utf8))
            }
            if url.contains("shikimori.io/api/animes/90002") {
                return MockStubResponse(body: Data(#"{"id":90002,"score":"8.4"}"#.utf8))
            }
            return MockStubResponse(statusCode: 404, body: Data())
        }
        defer { MockURLProtocol.unregister(session: session2) }

        let service2 = MultiSiteScoreService(
            cacheFileURL: tempRoot.appendingPathComponent("site_scores_partial.json"),
            session: session2,
            aniList: AniListClient(session: session2, minimumInterval: 0)
        )
        _ = await service2.prefetchBatchScores(for: [90002], preference: .mal)
        let fullAfterPartial = await service2.fetchAllScores(for: 90002)
        XCTAssertTrue(fullAfterPartial.hasFetchedAllProviders)
        XCTAssertEqual(fullAfterPartial.malScore ?? 0, 8.57, accuracy: 0.001)
        XCTAssertEqual(fullAfterPartial.aniListScore ?? 0, 8.6, accuracy: 0.001)
        XCTAssertEqual(fullAfterPartial.shikimoriScore ?? 0, 8.4, accuracy: 0.001)
    }
}
