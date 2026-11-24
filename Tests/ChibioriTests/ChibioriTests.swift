import XCTest
import SwiftData
@testable import ChibioriCore

final class ChibioriTests: XCTestCase {

    // MARK: - TrackedAnime Lifecycle & Timestamps

    func testTrackedAnimeInitialStateAndReQueue() throws {
        let anime = TrackedAnime(
            malID: 5114,
            title: "Fullmetal Alchemist: Brotherhood",
            synopsis: "Two brothers search for the Philosopher's Stone.",
            coverImageRemoteURL: "https://cdn.myanimelist.net/images/anime/1208/94745.jpg",
            airingStatusRaw: "Finished Airing",
            totalEpisodes: 64
        )

        XCTAssertEqual(anime.malID, 5114)
        XCTAssertEqual(anime.watchStatus, .planToWatch)
        XCTAssertEqual(anime.currentEpisodeProgress, 0)
        XCTAssertNil(anime.dateStarted)
        XCTAssertNil(anime.dateCompleted)

        let initialDateAdded = anime.dateAdded
        Thread.sleep(forTimeInterval: 0.02)
        anime.reQueue()

        XCTAssertGreaterThan(anime.dateAdded, initialDateAdded)
        XCTAssertEqual(anime.watchStatus, .planToWatch)
    }

    func testTrackedAnimeStatusTransitions() throws {
        let anime = TrackedAnime(
            malID: 1,
            title: "Cowboy Bebop",
            synopsis: "Space bounty hunters.",
            coverImageRemoteURL: "",
            airingStatusRaw: "Finished Airing",
            totalEpisodes: 26
        )

        anime.setWatchStatus(.watching)
        XCTAssertEqual(anime.watchStatus, .watching)
        XCTAssertNotNil(anime.dateStarted)
        XCTAssertNil(anime.dateCompleted)

        let initialStarted = anime.dateStarted

        anime.setWatchStatus(.completed)
        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertNotNil(anime.dateCompleted)
        XCTAssertEqual(anime.currentEpisodeProgress, 26)
        XCTAssertEqual(anime.dateStarted, initialStarted)
    }

    func testTrackedAnimeEpisodeIncrementAndAutoComplete() throws {
        let anime = TrackedAnime(
            malID: 2,
            title: "Short Anime",
            synopsis: "Short series.",
            coverImageRemoteURL: "",
            airingStatusRaw: "Finished Airing",
            totalEpisodes: 3
        )

        XCTAssertEqual(anime.currentEpisodeProgress, 0)
        anime.incrementProgress()
        XCTAssertEqual(anime.currentEpisodeProgress, 1)
        XCTAssertEqual(anime.watchStatus, .watching)

        anime.incrementProgress()
        XCTAssertEqual(anime.currentEpisodeProgress, 2)
        XCTAssertEqual(anime.watchStatus, .watching)

        anime.incrementProgress()
        XCTAssertEqual(anime.currentEpisodeProgress, 3)
        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertNotNil(anime.dateCompleted)

        // Further increment stays capped at total episodes
        anime.incrementProgress()
        XCTAssertEqual(anime.currentEpisodeProgress, 3)
    }

    // MARK: - AiringStatus & Date Formatter

    func testAiringStatusParsingAndDateFormatting() {
        XCTAssertEqual(AiringStatus.from(raw: "Currently Airing"), .currentlyAiring)
        XCTAssertEqual(AiringStatus.from(raw: "airing"), .currentlyAiring)
        XCTAssertEqual(AiringStatus.from(raw: "RELEASING"), .currentlyAiring)
        XCTAssertEqual(AiringStatus.from(raw: "Finished Airing"), .finishedAiring)
        XCTAssertEqual(AiringStatus.from(raw: "completed"), .finishedAiring)
        XCTAssertEqual(AiringStatus.from(raw: "Not Yet Aired"), .notYetAired)
        XCTAssertEqual(AiringStatus.from(raw: "upcoming"), .notYetAired)

        XCTAssertEqual(AnimeDateFormatter.format(year: 2026, month: 8, day: 14), "14th Aug 2026")
        XCTAssertEqual(AnimeDateFormatter.format(rawDateString: "2009-04-05"), "5th Apr 2009")
        XCTAssertEqual(AnimeDateFormatter.format(rawDateString: "14th Aug 2026"), "14th Aug 2026")
        XCTAssertNil(AnimeDateFormatter.format(rawDateString: "0000-00-00"))
    }

    // MARK: - Backup JSON Schema & Extended Fields Round-Trip

    @MainActor
    func testBackupServiceRoundTripWithExtendedAndLegacyFields() throws {
        // 1. Legacy payload without dubbedLanguages / bannerImageRemoteURL
        let legacyJSON = """
        {
          "version": "1.0",
          "exportedAt": "2026-08-13T15:30:00Z",
          "app": "Chibiori",
          "records": [
            {
              "malID": 5114,
              "title": "Fullmetal Alchemist: Brotherhood",
              "watchStatus": "completed",
              "currentEpisodeProgress": 64,
              "userRating": 10,
              "personalNotes": "Masterpiece pacing and ending.",
              "dateAdded": "2026-01-10T10:00:00Z",
              "dateStarted": "2026-01-11T12:00:00Z",
              "dateCompleted": "2026-01-25T18:30:00Z",
              "airingStatus": "Finished Airing",
              "totalEpisodes": 64,
              "malScore": 9.1,
              "coverImageRemoteURL": "https://cdn.myanimelist.net/images/anime/1208/94745.jpg"
            }
          ]
        }
        """

        let schema = Schema([TrackedAnime.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let summary = try BackupService.shared.importBackup(data: Data(legacyJSON.utf8), context: context)
        XCTAssertEqual(summary.totalParsed, 1)
        XCTAssertEqual(summary.insertedCount, 1)
        XCTAssertEqual(summary.updatedCount, 0)

        let items = try context.fetch(FetchDescriptor<TrackedAnime>())
        XCTAssertEqual(items.count, 1)
        let imported = items[0]
        imported.dubbedLanguages = ["Japanese", "English", "Hindi"]
        imported.bannerImageRemoteURL = "https://example.com/banner.jpg"

        let exportedData = try BackupService.shared.generateExportData(from: items)
        let decodedRoot = try JSONDecoder().decode(AnimeBackupRoot.self, from: exportedData)

        XCTAssertEqual(decodedRoot.version, "1.0")
        XCTAssertEqual(decodedRoot.app, "Chibiori")
        XCTAssertEqual(decodedRoot.records.count, 1)
        XCTAssertEqual(decodedRoot.records[0].dubbedLanguages, ["Japanese", "English", "Hindi"])
        XCTAssertEqual(decodedRoot.records[0].bannerImageRemoteURL, "https://example.com/banner.jpg")

        // Re-import into fresh store and verify extended fields survive round-trip
        let container2 = try ModelContainer(for: schema, configurations: [config])
        let context2 = ModelContext(container2)
        _ = try BackupService.shared.importBackup(data: exportedData, context: context2)
        let reimported = try context2.fetch(FetchDescriptor<TrackedAnime>())
        XCTAssertEqual(reimported.first?.dubbedLanguages, ["Japanese", "English", "Hindi"])
        XCTAssertEqual(reimported.first?.bannerImageRemoteURL, "https://example.com/banner.jpg")
    }

    // MARK: - MAL XML Parser

    func testMALXMLParserStatusFilteringAndFieldExtraction() throws {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <myanimelist>
            <myinfo>
                <user_id>12345</user_id>
                <user_name>Ghostkwebb</user_name>
            </myinfo>
            <anime>
                <series_animedb_id>5114</series_animedb_id>
                <series_title>Fullmetal Alchemist: Brotherhood</series_title>
                <series_type>1</series_type>
                <series_episodes>64</series_episodes>
                <series_start>2009-04-05</series_start>
                <series_end>2010-07-04</series_end>
                <my_id>0</my_id>
                <my_watched_episodes>64</my_watched_episodes>
                <my_score>10</my_score>
                <my_status>Completed</my_status>
                <my_comments><![CDATA[Favorite show]]></my_comments>
            </anime>
            <anime>
                <series_animedb_id>40748</series_animedb_id>
                <series_title>Jujutsu Kaisen</series_title>
                <series_type>1</series_type>
                <series_episodes>24</series_episodes>
                <my_id>0</my_id>
                <my_watched_episodes>12</my_watched_episodes>
                <my_score>8</my_score>
                <my_status>Watching</my_status>
            </anime>
            <anime>
                <series_animedb_id>31240</series_animedb_id>
                <series_title>Re:Zero</series_title>
                <series_type>1</series_type>
                <series_episodes>25</series_episodes>
                <my_id>0</my_id>
                <my_watched_episodes>0</my_watched_episodes>
                <my_score>0</my_score>
                <my_status>Plan to Watch</my_status>
            </anime>
        </myanimelist>
        """
        let xmlData = Data(sampleXML.utf8)

        let completedOnly = MALXMLParser.parse(data: xmlData, allowedStatuses: [.completed])
        XCTAssertEqual(completedOnly.count, 1)
        XCTAssertEqual(completedOnly[0].malID, 5114)
        XCTAssertEqual(completedOnly[0].status, .completed)
        XCTAssertEqual(completedOnly[0].userRating, 10)
        XCTAssertEqual(completedOnly[0].seriesStart, "5th Apr 2009")
        XCTAssertEqual(completedOnly[0].seriesEnd, "4th Jul 2010")

        let allItems = MALXMLParser.parse(data: xmlData, allowedStatuses: nil)
        XCTAssertEqual(allItems.count, 3)
    }

    // MARK: - TitleResolvable, Romaji Preservation & HTMLCleaner

    func testTitleLanguageResolutionCustomOverrideAndHTMLCleaner() {
        let anime = TrackedAnime(
            malID: 48760,
            title: "Gaikotsu Kishi-sama, Tadaima Isekai e Odekakechuu",
            synopsis: "Skeleton Knight wakes up in another world.",
            coverImageRemoteURL: "https://example.com/cover.jpg",
            airingStatusRaw: "Finished Airing",
            englishTitle: "Skeleton Knight in Another World",
            japaneseTitle: "骸骨騎士様、只今異世界へお出掛け中",
            totalEpisodes: 12
        )

        XCTAssertEqual(anime.displayTitle(for: .romaji), "Gaikotsu Kishi-sama, Tadaima Isekai e Odekakechuu")
        XCTAssertEqual(anime.displayTitle(for: .english), "Skeleton Knight in Another World")
        XCTAssertEqual(anime.displayTitle(for: .native), "骸骨騎士様、只今異世界へお出掛け中")

        anime.customTitleOverride = "Skeleton Knight Custom"
        XCTAssertEqual(anime.displayTitle(for: .romaji), "Skeleton Knight Custom")
        XCTAssertEqual(anime.displayTitle(for: .english), "Skeleton Knight Custom")

        let cleaned = HTMLCleaner.strip(from: "<p>Hello &quot;World&quot;<br/>Line &amp; <b>Two</b> &#039;Ok&#039;</p>")
        XCTAssertEqual(cleaned, "Hello \"World\"\nLine & Two 'Ok'")
    }

    // MARK: - NavigationState Isolated Persistence & Grid Zoom

    func testNavigationStatePersistenceAndZoomBounds() throws {
        let suiteName = "ChibioriTests.Nav.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let nav = NavigationState(defaults: defaults)
        XCTAssertEqual(nav.gridCardSize, 165.0)

        for _ in 0..<20 { nav.zoomInGrid() }
        XCTAssertLessThanOrEqual(nav.gridCardSize, 260.0)

        for _ in 0..<30 { nav.zoomOutGrid() }
        XCTAssertGreaterThanOrEqual(nav.gridCardSize, 110.0)

        nav.resetGridSize()
        XCTAssertEqual(nav.gridCardSize, 165.0)

        nav.selectedSidebar = .watchStatus(.completed)
        nav.showInspector = false
        nav.viewMode = .table
        nav.selectedSortOption = .scoreDesc
        nav.titleLanguagePreference = .romaji

        let navReloaded = NavigationState(defaults: defaults)
        XCTAssertEqual(navReloaded.selectedSidebar, .watchStatus(.completed))
        XCTAssertFalse(navReloaded.showInspector)
        XCTAssertEqual(navReloaded.viewMode, .table)
        XCTAssertEqual(navReloaded.selectedSortOption, .scoreDesc)
        XCTAssertEqual(navReloaded.titleLanguagePreference, .romaji)
    }

    // MARK: - UpdateManager Semver & Asset Selection

    @MainActor
    func testUpdateManagerSemverAndReleaseAssets() {
        XCTAssertTrue(UpdateManager.isVersion("v1.0.21", newerThan: "1.0.20"))
        XCTAssertTrue(UpdateManager.isVersion("2.0.0", newerThan: "v1.9.9"))
        XCTAssertFalse(UpdateManager.isVersion("v1.0.20", newerThan: "1.0.20"))
        XCTAssertFalse(UpdateManager.isVersion("v1.0.19", newerThan: "1.0.20"))

        let zip = GitHubReleaseAsset(name: "Chibiori.zip", browser_download_url: "https://example.com/a.zip", size: 100)
        let dmg = GitHubReleaseAsset(name: "Chibiori.dmg", browser_download_url: "https://example.com/a.dmg", size: 200)
        let releaseWithDmg = GitHubRelease(tag_name: "v1.0.21", name: nil, body: nil, published_at: nil, html_url: "https://example.com", assets: [zip, dmg])
        XCTAssertEqual(releaseWithDmg.updateAsset, dmg)

        let releaseZipOnly = GitHubRelease(tag_name: "v1.0.21", name: nil, body: nil, published_at: nil, html_url: "https://example.com", assets: [zip])
        XCTAssertEqual(releaseZipOnly.updateAsset, zip)
    }

    // MARK: - RelatedAnimeItem & DubbedLanguage Models

    func testRelatedAnimeItemPriorityAndDTO() {
        let prequel = RelatedAnimeItem(malID: 1, relationType: "PREQUEL", title: "Part 1", format: "TV", episodes: 12, seasonYear: 2022)
        let sequel = RelatedAnimeItem(malID: 2, relationType: "SEQUEL", title: "Part 2", format: "TV", episodes: 12, seasonYear: 2024)
        let side = RelatedAnimeItem(malID: 3, relationType: "SIDE_STORY", title: "OVA", format: "OVA", episodes: 1, seasonYear: 2023)

        XCTAssertLessThan(prequel.priorityRank, sequel.priorityRank)
        XCTAssertLessThan(sequel.priorityRank, side.priorityRank)
        XCTAssertEqual(sequel.asJikanDTO.malId, 2)
        XCTAssertEqual(sequel.asJikanDTO.episodes, 12)
    }

    func testDubbedLanguageResolutionAndTrackedAnimeIntegration() {
        let en = DubbedLanguage.resolve(from: "English")
        XCTAssertEqual(en.code, "EN")
        XCTAssertFalse(en.isNativeAudio)

        let hi = DubbedLanguage.resolve(from: "hindi")
        XCTAssertEqual(hi.code, "HI")
        XCTAssertEqual(hi.nativeName, "हिन्दी")

        let anime = TrackedAnime(
            malID: 999,
            title: "Dubbed Show",
            synopsis: "",
            coverImageRemoteURL: "",
            airingStatusRaw: "Finished Airing",
            dubbedLanguages: ["Hindi", "Japanese", "English"]
        )
        let resolved = anime.resolvedDubbedLanguages
        XCTAssertEqual(resolved.first?.code, "JP")
        XCTAssertTrue(resolved.contains(where: { $0.code == "EN" }))
        XCTAssertTrue(resolved.contains(where: { $0.code == "HI" }))
    }
}
