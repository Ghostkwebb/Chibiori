import Foundation
import SwiftData

public final class SmokeTestRunner {
    @MainActor
    public static func runAllTests() async -> Bool {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Chibiori Automated Smoke Test Suite")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        var passedCount = 0
        var failedCount = 0

        func check(_ testName: String, test: () throws -> Void) {
            do {
                try test()
                print("  ✅ PASS: \(testName)")
                passedCount += 1
            } catch {
                print("  ❌ FAIL: \(testName) - \(error.localizedDescription)")
                failedCount += 1
            }
        }

        func checkAsync(_ testName: String, test: () async throws -> Void) async {
            do {
                try await test()
                print("  ✅ PASS: \(testName)")
                passedCount += 1
            } catch {
                print("  ❌ FAIL: \(testName) - \(error.localizedDescription)")
                failedCount += 1
            }
        }

        // Test 1: TrackedAnime initialization & re-queuing
        check("TrackedAnime initialization and re-queuing mechanics") {
            let anime = TrackedAnime(
                malID: 5114,
                title: "Fullmetal Alchemist: Brotherhood",
                synopsis: "Two brothers search for the Philosopher's Stone.",
                coverImageRemoteURL: "https://cdn.myanimelist.net/images/anime/1208/94745.jpg",
                airingStatusRaw: "Finished Airing",
                totalEpisodes: 64
            )
            guard anime.malID == 5114 else { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "malID mismatch"]) }
            guard anime.watchStatus == .planToWatch else { throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial status should be planToWatch"]) }
            guard anime.currentEpisodeProgress == 0 else { throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Initial progress should be 0"]) }
            guard anime.dateStarted == nil && anime.dateCompleted == nil else { throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Timestamps should be nil initially"]) }

            let originalDateAdded = anime.dateAdded
            Thread.sleep(forTimeInterval: 0.02)
            anime.reQueue()

            guard anime.dateAdded >= originalDateAdded else { throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Re-queue failed to update dateAdded"]) }
        }

        // Test 2: Watch status transitions and lifecycle timestamps
        check("Watch status transitions and timestamp lifecycle") {
            let anime = TrackedAnime(
                malID: 1,
                title: "Cowboy Bebop",
                synopsis: "Space bounty hunters.",
                coverImageRemoteURL: "",
                airingStatusRaw: "Finished Airing",
                totalEpisodes: 26
            )

            // Shift to Watching
            anime.setWatchStatus(.watching)
            guard anime.watchStatus == .watching else { throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed shift to watching"]) }
            guard anime.dateStarted != nil else { throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "dateStarted not recorded on shift to watching"]) }

            let started = anime.dateStarted

            // Shift to Completed
            anime.setWatchStatus(.completed)
            guard anime.watchStatus == .completed else { throw NSError(domain: "Test", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed shift to completed"]) }
            guard anime.dateCompleted != nil else { throw NSError(domain: "Test", code: 13, userInfo: [NSLocalizedDescriptionKey: "dateCompleted not recorded on shift to completed"]) }
            guard anime.currentEpisodeProgress == 26 else { throw NSError(domain: "Test", code: 14, userInfo: [NSLocalizedDescriptionKey: "Current episode progress not auto-completed"]) }
            guard anime.dateStarted == started else { throw NSError(domain: "Test", code: 15, userInfo: [NSLocalizedDescriptionKey: "Historical dateStarted corrupted"]) }
        }

        // Test 3: Episode increment and auto-completion
        check("Episode progress increments and completion trigger") {
            let anime = TrackedAnime(
                malID: 2,
                title: "Trigun",
                synopsis: "Vash the Stampede.",
                coverImageRemoteURL: "",
                airingStatusRaw: "Finished Airing",
                totalEpisodes: 2
            )

            anime.incrementProgress()
            guard anime.currentEpisodeProgress == 1 && anime.watchStatus == .watching else { throw NSError(domain: "Test", code: 20, userInfo: [NSLocalizedDescriptionKey: "Increment to 1 failed"]) }

            anime.incrementProgress()
            guard anime.currentEpisodeProgress == 2 && anime.watchStatus == .completed else { throw NSError(domain: "Test", code: 21, userInfo: [NSLocalizedDescriptionKey: "Auto-complete on max episodes failed"]) }

            // Guard against overflowing max
            anime.incrementProgress()
            guard anime.currentEpisodeProgress == 2 else { throw NSError(domain: "Test", code: 22, userInfo: [NSLocalizedDescriptionKey: "Progress exceeded total episodes"]) }
        }

        // Test 4: AiringStatus & AnimeDateFormatter parsing
        check("AiringStatus parser string variations and AnimeDateFormatter") {
            guard AiringStatus.from(raw: "Currently Airing") == .currentlyAiring else { throw NSError(domain: "Test", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed currently airing parse"]) }
            guard AiringStatus.from(raw: "RELEASING") == .currentlyAiring else { throw NSError(domain: "Test", code: 31, userInfo: [NSLocalizedDescriptionKey: "Failed RELEASING parse"]) }
            guard AiringStatus.from(raw: "Finished Airing") == .finishedAiring else { throw NSError(domain: "Test", code: 32, userInfo: [NSLocalizedDescriptionKey: "Failed finished airing parse"]) }
            guard AiringStatus.from(raw: "FINISHED") == .finishedAiring else { throw NSError(domain: "Test", code: 33, userInfo: [NSLocalizedDescriptionKey: "Failed FINISHED parse"]) }
            guard AiringStatus.from(raw: "Not Yet Aired") == .notYetAired else { throw NSError(domain: "Test", code: 34, userInfo: [NSLocalizedDescriptionKey: "Failed not yet aired parse"]) }
            guard AiringStatus.from(raw: "NOT_YET_RELEASED") == .notYetAired else { throw NSError(domain: "Test", code: 35, userInfo: [NSLocalizedDescriptionKey: "Failed NOT_YET_RELEASED parse"]) }
            guard AiringStatus.from(raw: "1") == .currentlyAiring else { throw NSError(domain: "Test", code: 36, userInfo: [NSLocalizedDescriptionKey: "Failed 1 series_status parse"]) }

            // Date formatting
            guard AnimeDateFormatter.format(rawDateString: "2026-08-14") == "14th Aug 2026" else {
                throw NSError(domain: "Test", code: 37, userInfo: [NSLocalizedDescriptionKey: "Failed 14th Aug 2026 date format"])
            }
            guard AnimeDateFormatter.format(year: 2026, month: 1, day: 1) == "1st Jan 2026" else {
                throw NSError(domain: "Test", code: 38, userInfo: [NSLocalizedDescriptionKey: "Failed 1st Jan 2026 date format"])
            }

            // Test airingDatesDisplay across different airing statuses
            // 1. Finished Airing with start and end dates
            let finishedAnime = TrackedAnime(
                malID: 63508,
                title: "From Overshadowed to Overpowered",
                synopsis: "Sage rebirth",
                coverImageRemoteURL: "",
                airingStatusRaw: "Finished Airing",
                seasonYear: "2026-06-26",
                airingEndDate: "2026-09-11"
            )
            guard finishedAnime.airingDatesDisplay == "26th Jun 2026 – 11th Sep 2026" else {
                throw NSError(domain: "Test", code: 39, userInfo: [NSLocalizedDescriptionKey: "Finished airing date range mismatch: \(finishedAnime.airingDatesDisplay ?? "nil")"])
            }

            // 2. Finished Airing single-day release (same start and end)
            let movieAnime = TrackedAnime(
                malID: 9999,
                title: "Anime Movie",
                synopsis: "Film",
                coverImageRemoteURL: "",
                airingStatusRaw: "Finished Airing",
                seasonYear: "2026-06-26",
                airingEndDate: "2026-06-26"
            )
            guard movieAnime.airingDatesDisplay == "26th Jun 2026" else {
                throw NSError(domain: "Test", code: 40, userInfo: [NSLocalizedDescriptionKey: "Single-day finished release should not repeat date: \(movieAnime.airingDatesDisplay ?? "nil")"])
            }

            // 3. Currently Airing (shows start date – Present)
            let airingAnime = TrackedAnime(
                malID: 10001,
                title: "Ongoing Show",
                synopsis: "Ongoing",
                coverImageRemoteURL: "",
                airingStatusRaw: "Currently Airing",
                seasonYear: "2026-06-26"
            )
            guard airingAnime.airingDatesDisplay == "26th Jun 2026 – Present" else {
                throw NSError(domain: "Test", code: 41, userInfo: [NSLocalizedDescriptionKey: "Currently airing show date format mismatch: \(airingAnime.airingDatesDisplay ?? "nil")"])
            }

            // 4. Not Yet Aired (shows scheduled release date without end date)
            let upcomingAnime = TrackedAnime(
                malID: 10002,
                title: "Upcoming Show",
                synopsis: "Upcoming",
                coverImageRemoteURL: "",
                airingStatusRaw: "Not Yet Aired",
                seasonYear: "2026-10-01"
            )
            guard upcomingAnime.airingDatesDisplay == "1st Oct 2026" else {
                throw NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Upcoming show date format mismatch: \(upcomingAnime.airingDatesDisplay ?? "nil")"])
            }

            let upcomingNoDate = TrackedAnime(
                malID: 10003,
                title: "TBA Show",
                synopsis: "TBA",
                coverImageRemoteURL: "",
                airingStatusRaw: "Not Yet Aired"
            )
            guard upcomingNoDate.airingDatesDisplay == "Upcoming" else {
                throw NSError(domain: "Test", code: 43, userInfo: [NSLocalizedDescriptionKey: "Upcoming show without date should return Upcoming: \(upcomingNoDate.airingDatesDisplay ?? "nil")"])
            }
        }

        // Test 5: JSON Backup Import/Export Round-Trip
        check("BackupService JSON specification round-trip") {
            let sampleJSON = """
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
                  "seasonYear": "2009-04-05",
                  "airingEndDate": "2010-07-04",
                  "totalEpisodes": 64,
                  "malScore": 9.1,
                  "coverImageRemoteURL": "https://cdn.myanimelist.net/images/anime/1208/94745.jpg"
                }
              ]
            }
            """
            guard let jsonData = sampleJSON.data(using: .utf8) else { throw NSError(domain: "Test", code: 40, userInfo: [NSLocalizedDescriptionKey: "Invalid sample JSON data"]) }

            let schema = Schema([TrackedAnime.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let summary = try BackupService.shared.importBackup(data: jsonData, context: context)
            guard summary.totalParsed == 1 && summary.insertedCount == 1 else { throw NSError(domain: "Test", code: 41, userInfo: [NSLocalizedDescriptionKey: "Import summary count mismatch"]) }

            let items = try context.fetch(FetchDescriptor<TrackedAnime>())
            guard items.count == 1 else { throw NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Fetched count mismatch"]) }

            let anime = items[0]
            guard anime.malID == 5114 && anime.watchStatus == .completed && anime.userRating == 10 && anime.currentEpisodeProgress == 64 && anime.airingEndDate == "2010-07-04" else {
                throw NSError(domain: "Test", code: 43, userInfo: [NSLocalizedDescriptionKey: "Imported anime field values mismatch"])
            }

            // Export test
            let exportedData = try BackupService.shared.generateExportData(from: items)
            let decodedRoot = try JSONDecoder().decode(AnimeBackupRoot.self, from: exportedData)
            guard decodedRoot.records.count == 1 && decodedRoot.records[0].malID == 5114 && decodedRoot.records[0].airingEndDate == "2010-07-04" else {
                throw NSError(domain: "Test", code: 44, userInfo: [NSLocalizedDescriptionKey: "Exported JSON structure mismatch"])
            }
        }

        // Test 6: Live JikanAPIService Network Throttling & Live API
        await checkAsync("JikanAPIService Live REST API fetch & throttling") {
            let results = try await JikanAPIService.shared.fetchCurrentSeason()
            guard !results.isEmpty else {
                throw NSError(domain: "Test", code: 50, userInfo: [NSLocalizedDescriptionKey: "Empty results returned for current season"])
            }
            guard results[0].malId > 0 && !results[0].title.isEmpty else {
                throw NSError(domain: "Test", code: 51, userInfo: [NSLocalizedDescriptionKey: "Malformed DTO fields"])
            }
        }

        // Test 7: MyAnimeList (MAL) XML Parser with Status Filter
        check("MALXMLParser status filtering and field extraction") {
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
            guard let xmlData = sampleXML.data(using: .utf8) else {
                throw NSError(domain: "Test", code: 60, userInfo: [NSLocalizedDescriptionKey: "Invalid sample XML"])
            }

            // Test completed only filter
            let completedOnly = MALXMLParser.parse(data: xmlData, allowedStatuses: [.completed])
            guard completedOnly.count == 1 else {
                throw NSError(domain: "Test", code: 61, userInfo: [NSLocalizedDescriptionKey: "Completed only filter should return exactly 1 item, got \(completedOnly.count)"])
            }
            guard completedOnly[0].malID == 5114 && completedOnly[0].status == .completed && completedOnly[0].userRating == 10 && completedOnly[0].seriesStart == "5th Apr 2009" && completedOnly[0].seriesEnd == "4th Jul 2010" else {
                throw NSError(domain: "Test", code: 62, userInfo: [NSLocalizedDescriptionKey: "Completed item field mismatch or series_end parsing failed"])
            }

            // Test all statuses
            let allItems = MALXMLParser.parse(data: xmlData, allowedStatuses: nil)
            guard allItems.count == 3 else {
                throw NSError(domain: "Test", code: 63, userInfo: [NSLocalizedDescriptionKey: "All statuses should return 3 items, got \(allItems.count)"])
            }
        }

        // Test 8: Sequel Alert Data Model Integrity
        check("SequelAlertItem model initialization and equatable conformance") {
            let item = SequelAlertItem(
                parentMalId: 40748,
                parentTitle: "Jujutsu Kaisen",
                sequelMalId: 51009,
                sequelTitle: "Jujutsu Kaisen 2nd Season",
                sequelCoverImageURL: "https://example.com/jjk2.jpg",
                sequelStatus: "NOT_YET_RELEASED",
                airingSeasonYear: "Fall 2026",
                synopsis: "The Shibuya Incident."
            )
            guard item.id == 51009 && item.parentMalId == 40748 else {
                throw NSError(domain: "Test", code: 70, userInfo: [NSLocalizedDescriptionKey: "SequelAlertItem identifier mismatch"])
            }
            guard item.airingSeasonYear == "Fall 2026" else {
                throw NSError(domain: "Test", code: 71, userInfo: [NSLocalizedDescriptionKey: "Season year mismatch"])
            }
        }

        // Test 9: MetadataHydrationService Batch Fetching
        await checkAsync("MetadataHydrationService batch poster metadata fetch") {
            let schema = Schema([TrackedAnime.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let testAnime = TrackedAnime(
                malID: 55791,
                title: "[Oshi no Ko] 2nd Season",
                synopsis: "",
                coverImageRemoteURL: "",
                airingStatusRaw: "Finished Airing"
            )
            context.insert(testAnime)
            try context.save()

            await MetadataHydrationService.shared.hydrateMissingMetadata(context: context)

            guard !testAnime.coverImageRemoteURL.isEmpty else {
                throw NSError(domain: "Test", code: 80, userInfo: [NSLocalizedDescriptionKey: "Failed to hydrate coverImageRemoteURL"])
            }
        }

        // Test 10: Apple CloudKit & iCloud Drive Auto-Vault Pipeline
        check("CloudSyncService iCloud auto-vault serialization and availability") {
            let anime = TrackedAnime(
                malID: 5114,
                title: "Fullmetal Alchemist: Brotherhood",
                synopsis: "Alchemy journey",
                coverImageRemoteURL: "https://example.com/fma.jpg",
                airingStatusRaw: "Finished Airing"
            )
            CloudSyncService.shared.performAutoCloudBackup(from: [anime])
            guard CloudSyncService.shared.isCloudSyncEnabled else {
                throw NSError(domain: "Test", code: 90, userInfo: [NSLocalizedDescriptionKey: "Cloud sync is disabled"])
            }
        }

        // Test 11: UpdateManager Semantic Versioning & GitHub Releases Comparison
        check("UpdateManager semver comparison logic") {
            guard UpdateManager.isVersion("v1.0.1", newerThan: "1.0.0") else {
                throw NSError(domain: "Test", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed: v1.0.1 should be newer than 1.0.0"])
            }
            guard UpdateManager.isVersion("v2.0.0", newerThan: "1.9.9") else {
                throw NSError(domain: "Test", code: 101, userInfo: [NSLocalizedDescriptionKey: "Failed: v2.0.0 should be newer than 1.9.9"])
            }
            guard !UpdateManager.isVersion("v1.0.0", newerThan: "1.0.0") else {
                throw NSError(domain: "Test", code: 102, userInfo: [NSLocalizedDescriptionKey: "Failed: v1.0.0 is not newer than 1.0.0"])
            }
            guard !UpdateManager.isVersion("v0.9.5", newerThan: "1.0.0") else {
                throw NSError(domain: "Test", code: 103, userInfo: [NSLocalizedDescriptionKey: "Failed: v0.9.5 is not newer than 1.0.0"])
            }
        }

        // Test 12: TitleLanguagePreference fallback resolution and HTML tag stripper
        check("TitleLanguagePreference resolution and HTML tag stripper") {
            let anime = TrackedAnime(
                malID: 49818,
                title: "Guimi Zhi Zhu: Xiaochou Pian",
                synopsis: "The second season of <i>Guimi Zhi Zhu</i>.<br>An epic journey.",
                coverImageRemoteURL: "https://example.com/lotm.jpg",
                airingStatusRaw: "Finished Airing",
                englishTitle: "Lord of the Mysteries",
                japaneseTitle: "诡秘之主"
            )

            // Test English preference
            guard anime.displayTitle(for: .english) == "Lord of the Mysteries" else {
                throw NSError(domain: "Test", code: 110, userInfo: [NSLocalizedDescriptionKey: "English title resolution failed"])
            }
            // Test Romaji preference
            guard anime.displayTitle(for: .romaji) == "Guimi Zhi Zhu: Xiaochou Pian" else {
                throw NSError(domain: "Test", code: 111, userInfo: [NSLocalizedDescriptionKey: "Romaji title resolution failed"])
            }
            // Test Native preference
            guard anime.displayTitle(for: .native) == "诡秘之主" else {
                throw NSError(domain: "Test", code: 112, userInfo: [NSLocalizedDescriptionKey: "Native title resolution failed"])
            }

            // Test custom title override
            anime.customTitleOverride = "LOTM Season 1"
            guard anime.displayTitle(for: .english) == "LOTM Season 1" else {
                throw NSError(domain: "Test", code: 113, userInfo: [NSLocalizedDescriptionKey: "Custom override resolution failed"])
            }
            anime.customTitleOverride = nil

            // Test HTML tag stripper
            let cleanSynopsis = MetadataHydrationService.stripHTMLTags(from: anime.synopsis)
            guard cleanSynopsis == "The second season of Guimi Zhi Zhu.\nAn epic journey." else {
                throw NSError(domain: "Test", code: 114, userInfo: [NSLocalizedDescriptionKey: "HTML tag stripping failed: \(cleanSynopsis ?? "")"])
            }

            // Test SequelAlertItem title resolution
            let alert = SequelAlertItem(
                parentMalId: 49818,
                parentTitle: "Guimi Zhi Zhu: Xiaochou Pian",
                parentEnglishTitle: "Lord of the Mysteries",
                parentJapaneseTitle: "诡秘之主",
                sequelMalId: 63632,
                sequelTitle: "Guimi Zhi Zhu: Wu Mian Ren Pian",
                sequelEnglishTitle: "Lord of the Mysteries: Faceless",
                sequelJapaneseTitle: "诡秘之主：无面人篇",
                sequelCoverImageURL: "https://example.com/lotm2.jpg",
                sequelStatus: "NOT_YET_RELEASED"
            )

            guard alert.displaySequelTitle(for: .english) == "Lord of the Mysteries: Faceless" else {
                throw NSError(domain: "Test", code: 115, userInfo: [NSLocalizedDescriptionKey: "Sequel English title failed"])
            }
            guard alert.displaySequelTitle(for: .romaji) == "Guimi Zhi Zhu: Wu Mian Ren Pian" else {
                throw NSError(domain: "Test", code: 116, userInfo: [NSLocalizedDescriptionKey: "Sequel Romaji title failed"])
            }
            guard alert.displaySequelTitle(for: .native) == "诡秘之主：无面人篇" else {
                throw NSError(domain: "Test", code: 117, userInfo: [NSLocalizedDescriptionKey: "Sequel Native title failed"])
            }
        }

        // Test 13: NavigationState Grid Card Size Slider & Zoom Mechanics
        check("NavigationState Grid Card Size slider & zoom boundaries") {
            let navState = NavigationState()
            navState.resetGridSize()
            guard navState.gridCardSize == 165.0 else {
                throw NSError(domain: "Test", code: 120, userInfo: [NSLocalizedDescriptionKey: "Initial grid size must be 165"])
            }

            // Test zoom in
            navState.zoomInGrid()
            guard navState.gridCardSize == 185.0 else {
                throw NSError(domain: "Test", code: 121, userInfo: [NSLocalizedDescriptionKey: "Zoom in failed to add 20pt"])
            }

            // Test max boundary clamping
            for _ in 0..<10 {
                navState.zoomInGrid()
            }
            guard navState.gridCardSize == 260.0 else {
                throw NSError(domain: "Test", code: 122, userInfo: [NSLocalizedDescriptionKey: "Max zoom should clamp to 260"])
            }

            // Test min boundary clamping
            for _ in 0..<20 {
                navState.zoomOutGrid()
            }
            guard navState.gridCardSize == 110.0 else {
                throw NSError(domain: "Test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Min zoom should clamp to 110"])
            }

            // Test reset
            navState.resetGridSize()
            guard navState.gridCardSize == 165.0 else {
                throw NSError(domain: "Test", code: 124, userInfo: [NSLocalizedDescriptionKey: "Reset failed to restore 165pt"])
            }
        }

        // Test 14: NavigationState Sidebar/Inspector/ViewMode/Sort Persistence
        check("NavigationState sidebar, inspector, viewMode, sortOption persistence") {
            let state1 = NavigationState()
            state1.sidebarWidth = 275.0
            state1.inspectorWidth = 410.0
            state1.showInspector = false
            state1.viewMode = .table
            state1.selectedSortOption = .scoreDesc
            state1.selectedSidebar = .watchStatus(.completed)

            // Re-instantiate new NavigationState to verify loaded values from UserDefaults
            let state2 = NavigationState()
            guard state2.sidebarWidth == 275.0 else {
                throw NSError(domain: "Test", code: 130, userInfo: [NSLocalizedDescriptionKey: "Sidebar width persistence failed: \(state2.sidebarWidth)"])
            }
            guard state2.inspectorWidth == 410.0 else {
                throw NSError(domain: "Test", code: 131, userInfo: [NSLocalizedDescriptionKey: "Inspector width persistence failed: \(state2.inspectorWidth)"])
            }
            guard state2.showInspector == false else {
                throw NSError(domain: "Test", code: 132, userInfo: [NSLocalizedDescriptionKey: "Show inspector persistence failed"])
            }
            guard state2.viewMode == .table else {
                throw NSError(domain: "Test", code: 133, userInfo: [NSLocalizedDescriptionKey: "View mode persistence failed: \(state2.viewMode)"])
            }
            guard state2.selectedSortOption == .scoreDesc else {
                throw NSError(domain: "Test", code: 134, userInfo: [NSLocalizedDescriptionKey: "Sort option persistence failed"])
            }
            guard state2.selectedSidebar == .watchStatus(.completed) else {
                throw NSError(domain: "Test", code: 135, userInfo: [NSLocalizedDescriptionKey: "Sidebar selection persistence failed: \(String(describing: state2.selectedSidebar))"])
            }

            // Test SidebarSelection.from(id:) parser
            guard SidebarSelection.from(id: "allAnime") == .allAnime,
                  SidebarSelection.from(id: "search") == .search,
                  SidebarSelection.from(id: "weeklyCalendar") == .weeklyCalendar,
                  SidebarSelection.from(id: "sequelAlerts") == .sequelAlerts,
                  SidebarSelection.from(id: "backup") == .backup,
                  SidebarSelection.from(id: "status_planToWatch") == .watchStatus(.planToWatch) else {
                throw NSError(domain: "Test", code: 136, userInfo: [NSLocalizedDescriptionKey: "SidebarSelection.from(id:) failed"])
            }
        }

        // Test 15: RelatedAnimeItem properties, priority ranking, and DTO conversion
        check("RelatedAnimeItem properties, priority ranking, and DTO conversion") {
            let prequel = RelatedAnimeItem(
                malID: 40748,
                relationType: "PREQUEL",
                title: "Jujutsu Kaisen",
                englishTitle: "JUJUTSU KAISEN",
                japaneseTitle: "呪術廻戦",
                coverImageURL: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx113415-LHBAeoZDIsnF.jpg",
                format: "TV",
                status: "FINISHED",
                episodes: 24,
                season: "FALL",
                seasonYear: 2020
            )

            let sequel = RelatedAnimeItem(
                malID: 57658,
                relationType: "SEQUEL",
                title: "Jujutsu Kaisen: Shimetsu Kaiyuu",
                englishTitle: "JUJUTSU KAISEN: Culling Game",
                japaneseTitle: "呪術廻戦 死滅回游",
                coverImageURL: "https://example.com/cover.jpg",
                format: "TV",
                status: "NOT_YET_RELEASED",
                episodes: nil,
                season: nil,
                seasonYear: 2026
            )

            guard prequel.priorityRank < sequel.priorityRank else {
                throw NSError(domain: "Test", code: 140, userInfo: [NSLocalizedDescriptionKey: "Prequels must have higher priority rank than sequels"])
            }
            guard prequel.relationDisplayName == "Prequel" else {
                throw NSError(domain: "Test", code: 141, userInfo: [NSLocalizedDescriptionKey: "Prequel display name failed: \(prequel.relationDisplayName)"])
            }
            guard sequel.relationDisplayName == "Sequel" else {
                throw NSError(domain: "Test", code: 142, userInfo: [NSLocalizedDescriptionKey: "Sequel display name failed: \(sequel.relationDisplayName)"])
            }

            // Language resolution
            guard prequel.displayTitle(for: .english) == "JUJUTSU KAISEN" else {
                throw NSError(domain: "Test", code: 143, userInfo: [NSLocalizedDescriptionKey: "English title resolution failed"])
            }
            guard prequel.displayTitle(for: .romaji) == "Jujutsu Kaisen" else {
                throw NSError(domain: "Test", code: 144, userInfo: [NSLocalizedDescriptionKey: "Romaji title resolution failed"])
            }
            guard prequel.displayTitle(for: .native) == "呪術廻戦" else {
                throw NSError(domain: "Test", code: 145, userInfo: [NSLocalizedDescriptionKey: "Native title resolution failed"])
            }

            // Subtitle metadata
            guard prequel.metadataSubtitle.contains("24 eps") && prequel.metadataSubtitle.contains("2020") else {
                throw NSError(domain: "Test", code: 146, userInfo: [NSLocalizedDescriptionKey: "Metadata subtitle failed: \(prequel.metadataSubtitle)"])
            }

            // DTO conversion
            let dto = prequel.asJikanDTO
            guard dto.malId == 40748 && dto.titleEnglish == "JUJUTSU KAISEN" && dto.episodes == 24 else {
                throw NSError(domain: "Test", code: 147, userInfo: [NSLocalizedDescriptionKey: "asJikanDTO conversion failed"])
            }
            guard dto.status == "Finished Airing" else {
                throw NSError(domain: "Test", code: 148, userInfo: [NSLocalizedDescriptionKey: "DTO status mapping failed: \(String(describing: dto.status))"])
            }
            guard dto.seasonYearFormatted == "Fall 2020" else {
                throw NSError(domain: "Test", code: 149, userInfo: [NSLocalizedDescriptionKey: "DTO seasonYearFormatted failed"])
            }
            guard dto.airingDatesDisplay == "Fall 2020" else {
                throw NSError(domain: "Test", code: 150, userInfo: [NSLocalizedDescriptionKey: "DTO airingDatesDisplay failed"])
            }

            // Test sequel without aired object (guards against circular recursion stack overflow)
            let sequelDTO = sequel.asJikanDTO
            guard sequelDTO.seasonYearFormatted == "2026" else {
                throw NSError(domain: "Test", code: 151, userInfo: [NSLocalizedDescriptionKey: "Sequel DTO seasonYearFormatted failed"])
            }
            guard sequelDTO.startDateFormatted == nil else {
                throw NSError(domain: "Test", code: 152, userInfo: [NSLocalizedDescriptionKey: "Sequel DTO startDateFormatted should be nil when aired is nil"])
            }
            guard sequelDTO.airingDatesDisplay == "2026" else {
                throw NSError(domain: "Test", code: 153, userInfo: [NSLocalizedDescriptionKey: "Sequel DTO airingDatesDisplay failed: \(String(describing: sequelDTO.airingDatesDisplay))"])
            }
        }

        // Test 16: AnimeRelationsService cache and retrieval
        await checkAsync("AnimeRelationsService caching and retrieval") {
            let mockItem = RelatedAnimeItem(
                malID: 58567,
                relationType: "SEQUEL",
                title: "Solo Leveling Season 2",
                englishTitle: "Solo Leveling Season 2: Arise from the Shadow",
                coverImageURL: "https://example.com/sl2.jpg",
                format: "TV",
                status: "FINISHED",
                episodes: 13,
                seasonYear: 2025
            )

            AnimeRelationsService.shared.setCachedRelations([mockItem], for: 52299)
            let fetched = await AnimeRelationsService.shared.fetchRelations(for: 52299)

            guard fetched.count == 1, fetched.first?.malID == 58567 else {
                throw NSError(domain: "Test", code: 150, userInfo: [NSLocalizedDescriptionKey: "AnimeRelationsService failed to return cached relations"])
            }

            let empty = await AnimeRelationsService.shared.fetchRelations(for: -1)
            guard empty.isEmpty else {
                throw NSError(domain: "Test", code: 151, userInfo: [NSLocalizedDescriptionKey: "AnimeRelationsService should return empty for invalid ID"])
            }
        }

        // Test 17: Romaji Title Resolution and Preservation (Skeleton Knight test case)
        check("Romaji title resolution and preference toggling") {
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

            guard anime.displayTitle(for: .romaji) == "Gaikotsu Kishi-sama, Tadaima Isekai e Odekakechuu" else {
                throw NSError(domain: "Test", code: 160, userInfo: [NSLocalizedDescriptionKey: "Romaji title failed to display canonical romaji name"])
            }
            guard anime.displayTitle(for: .english) == "Skeleton Knight in Another World" else {
                throw NSError(domain: "Test", code: 161, userInfo: [NSLocalizedDescriptionKey: "English title failed to display english name"])
            }
            guard anime.displayTitle(for: .native) == "骸骨騎士様、只今異世界へお出掛け中" else {
                throw NSError(domain: "Test", code: 162, userInfo: [NSLocalizedDescriptionKey: "Native title failed to display japanese name"])
            }
        }

        // Test 18: DubbedLanguage Resolution and Code Normalization
        check("DubbedLanguage resolution, codes, and sorting priority") {
            let en = DubbedLanguage.resolve(from: "English")
            guard en.code == "EN" && en.name == "English" && !en.isNativeAudio else {
                throw NSError(domain: "Test", code: 170, userInfo: [NSLocalizedDescriptionKey: "English resolution failed"])
            }

            let hi = DubbedLanguage.resolve(from: "hindi")
            guard hi.code == "HI" && hi.nativeName == "हिन्दी" else {
                throw NSError(domain: "Test", code: 171, userInfo: [NSLocalizedDescriptionKey: "Hindi resolution failed"])
            }

            let zh = DubbedLanguage.resolve(from: "chinese")
            guard zh.code == "ZH" && zh.nativeName == "中文" else {
                throw NSError(domain: "Test", code: 172, userInfo: [NSLocalizedDescriptionKey: "Chinese resolution failed"])
            }

            let jp = DubbedLanguage.resolve(from: "Japanese", isNative: true)
            guard jp.code == "JP" && jp.isNativeAudio else {
                throw NSError(domain: "Test", code: 173, userInfo: [NSLocalizedDescriptionKey: "Japanese native resolution failed"])
            }

            guard jp.sortPriority < en.sortPriority && en.sortPriority < hi.sortPriority else {
                throw NSError(domain: "Test", code: 174, userInfo: [NSLocalizedDescriptionKey: "Sort priorities incorrect"])
            }
        }

        // Test 19: TrackedAnime Dubbed Languages Resolution and Formatting
        check("TrackedAnime dubbedLanguages resolution and display string") {
            let anime = TrackedAnime(
                malID: 20,
                title: "Naruto",
                synopsis: "Ninja story",
                coverImageRemoteURL: "https://example.com/naruto.jpg",
                airingStatusRaw: "Finished Airing",
                dubbedLanguages: ["English", "Hindi", "French", "Spanish"]
            )

            let resolved = anime.resolvedDubbedLanguages
            guard resolved.contains(where: { $0.code == "JP" && $0.isNativeAudio }) else {
                throw NSError(domain: "Test", code: 180, userInfo: [NSLocalizedDescriptionKey: "Should include default JP native audio"])
            }
            guard resolved.contains(where: { $0.code == "HI" }) else {
                throw NSError(domain: "Test", code: 181, userInfo: [NSLocalizedDescriptionKey: "Should resolve Hindi dub"])
            }
            guard resolved.contains(where: { $0.code == "EN" }) else {
                throw NSError(domain: "Test", code: 182, userInfo: [NSLocalizedDescriptionKey: "Should resolve English dub"])
            }

            let display = anime.dubbedLanguagesDisplay
            guard display.contains("Japanese (Original)") && display.contains("English") && display.contains("Hindi") else {
                throw NSError(domain: "Test", code: 183, userInfo: [NSLocalizedDescriptionKey: "Display string incorrect: \(display)"])
            }
        }

        // Test 20: DubbedLanguageService Multi-Language & English Dub Detection
        await checkAsync("DubbedLanguageService dataset loading and English dub verification") {
            let slimeHasEnglish = await DubbedLanguageService.shared.hasVerifiedEnglishDub(malId: 39551)
            guard slimeHasEnglish else {
                throw NSError(domain: "Test", code: 190, userInfo: [NSLocalizedDescriptionKey: "MAL ID 39551 (Slime S2) should have verified English dub"])
            }

            let skeletonHasEnglish = await DubbedLanguageService.shared.hasVerifiedEnglishDub(malId: 48760)
            guard skeletonHasEnglish else {
                throw NSError(domain: "Test", code: 191, userInfo: [NSLocalizedDescriptionKey: "MAL ID 48760 (Skeleton Knight) should have verified English dub"])
            }

            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: 39551)
            let codes = Set(dubs.map { $0.code })

            guard codes.contains("EN") else {
                throw NSError(domain: "Test", code: 192, userInfo: [NSLocalizedDescriptionKey: "Slime S2 dubs must include English (EN). Found: \(codes)"])
            }
            guard codes.contains("JP") else {
                throw NSError(domain: "Test", code: 193, userInfo: [NSLocalizedDescriptionKey: "Slime S2 dubs must include Japanese (JP). Found: \(codes)"])
            }
            guard codes.contains("HI") else {
                throw NSError(domain: "Test", code: 194, userInfo: [NSLocalizedDescriptionKey: "Slime S2 dubs must include Hindi (HI). Found: \(codes)"])
            }
        }

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Summary: \(passedCount) Passed, \(failedCount) Failed")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        return failedCount == 0
    }
}
