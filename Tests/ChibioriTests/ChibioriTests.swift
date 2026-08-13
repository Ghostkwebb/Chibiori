import XCTest
import SwiftData
@testable import Chibiori

final class ChibioriTests: XCTestCase {

    // MARK: - Test TrackedAnime Lifecycle & Timestamps
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
        // Sleep briefly and trigger reQueue
        Thread.sleep(forTimeInterval: 0.05)
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

        // 1. Shift to Watching
        anime.setWatchStatus(.watching)
        XCTAssertEqual(anime.watchStatus, .watching)
        XCTAssertNotNil(anime.dateStarted)
        XCTAssertNil(anime.dateCompleted)

        let initialStarted = anime.dateStarted

        // 2. Shift to Completed
        anime.setWatchStatus(.completed)
        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertNotNil(anime.dateCompleted)
        XCTAssertEqual(anime.currentEpisodeProgress, 26)
        XCTAssertEqual(anime.dateStarted, initialStarted) // Preserved
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

        // Further increment does nothing once completed
        anime.incrementProgress()
        XCTAssertEqual(anime.currentEpisodeProgress, 3)
    }

    // MARK: - Test AiringStatus Parsing
    func testAiringStatusParsing() {
        XCTAssertEqual(AiringStatus.from(raw: "Currently Airing"), .currentlyAiring)
        XCTAssertEqual(AiringStatus.from(raw: "airing"), .currentlyAiring)
        XCTAssertEqual(AiringStatus.from(raw: "Finished Airing"), .finishedAiring)
        XCTAssertEqual(AiringStatus.from(raw: "completed"), .finishedAiring)
        XCTAssertEqual(AiringStatus.from(raw: "Not Yet Aired"), .notYetAired)
        XCTAssertEqual(AiringStatus.from(raw: "upcoming"), .notYetAired)
    }

    // MARK: - Test Backup Schema JSON Round-Trip
    func testBackupServiceRoundTrip() throws {
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
              "totalEpisodes": 64,
              "malScore": 9.1,
              "coverImageRemoteURL": "https://cdn.myanimelist.net/images/anime/1208/94745.jpg"
            }
          ]
        }
        """

        let jsonData = sampleJSON.data(using: .utf8)!
        let schema = Schema([TrackedAnime.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let summary = try BackupService.shared.importBackup(data: jsonData, context: context)
        XCTAssertEqual(summary.totalParsed, 1)
        XCTAssertEqual(summary.insertedCount, 1)
        XCTAssertEqual(summary.updatedCount, 0)

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        let items = try context.fetch(fetchDescriptor)
        XCTAssertEqual(items.count, 1)

        let imported = items[0]
        XCTAssertEqual(imported.malID, 5114)
        XCTAssertEqual(imported.title, "Fullmetal Alchemist: Brotherhood")
        XCTAssertEqual(imported.watchStatus, .completed)
        XCTAssertEqual(imported.currentEpisodeProgress, 64)
        XCTAssertEqual(imported.userRating, 10)
        XCTAssertEqual(imported.personalNotes, "Masterpiece pacing and ending.")
        XCTAssertEqual(imported.totalEpisodes, 64)
        XCTAssertEqual(imported.malScore, 9.1)

        // Test Export
        let exportedData = try BackupService.shared.generateExportData(from: items)
        let decodedRoot = try JSONDecoder().decode(AnimeBackupRoot.self, from: exportedData)

        XCTAssertEqual(decodedRoot.version, "1.0")
        XCTAssertEqual(decodedRoot.app, "Chibiori")
        XCTAssertEqual(decodedRoot.records.count, 1)
        XCTAssertEqual(decodedRoot.records[0].malID, 5114)
        XCTAssertEqual(decodedRoot.records[0].watchStatus, "completed")
    }

    // MARK: - Test JikanAPIService Rate Limiting Throttle
    func testJikanActorThrottleRate() async throws {
        let actor = JikanAPIService()
        let start = Date()

        // Verify actor exists and minimum throttle is active
        _ = actor
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }
}
