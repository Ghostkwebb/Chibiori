import XCTest
import SwiftData
@testable import ChibioriCore

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempCloudFolder: URL!
    private var cloudSync: CloudSyncService!
    private var store: LibraryStore!

    override func setUp() async throws {
        let schema = Schema([TrackedAnime.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        tempCloudFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChibioriTests-LibraryStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempCloudFolder, withIntermediateDirectories: true)
        cloudSync = CloudSyncService(folderURL: tempCloudFolder)
        cloudSync.isCloudSyncEnabled = false

        store = LibraryStore(modelContext: context, cloudSync: cloudSync)
    }

    override func tearDown() async throws {
        store = nil
        cloudSync = nil
        context = nil
        container = nil
        if let tempCloudFolder {
            try? FileManager.default.removeItem(at: tempCloudFolder)
        }
    }

    func testStatusTransitionUpdatesCountsAndFiltersImmediately() throws {
        let dto = JikanAnimeDTO(
            malId: 40748,
            title: "Jujutsu Kaisen",
            titleEnglish: "Jujutsu Kaisen",
            status: "Finished Airing",
            episodes: 24
        )
        let anime = store.addOrUpdate(from: dto, status: .watching)

        XCTAssertEqual(store.statusCounts[.watching, default: 0], 1)
        XCTAssertEqual(store.statusCounts[.completed, default: 0], 0)
        XCTAssertEqual(store.filteredAnime(status: .watching, airing: nil, query: "", sortOption: .dateAddedDesc, titlePreference: .english).count, 1)

        // Transitioning Watching -> Completed must update counts & filters immediately
        store.setWatchStatus(.completed, for: anime)

        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertEqual(anime.currentEpisodeProgress, 24)
        XCTAssertNotNil(anime.dateCompleted)
        XCTAssertEqual(store.statusCounts[.watching, default: 0], 0)
        XCTAssertEqual(store.statusCounts[.completed, default: 0], 1)
        XCTAssertEqual(store.filteredAnime(status: .watching, airing: nil, query: "", sortOption: .dateAddedDesc, titlePreference: .english).count, 0)
        XCTAssertEqual(store.filteredAnime(status: .completed, airing: nil, query: "", sortOption: .dateAddedDesc, titlePreference: .english).count, 1)
    }

    func testAddOrUpdateDeduplicatesByMalID() throws {
        let dto1 = JikanAnimeDTO(malId: 5114, title: "Fullmetal Alchemist", status: "Finished Airing", episodes: 64)
        let first = store.addOrUpdate(from: dto1, status: .planToWatch)

        let dto2 = JikanAnimeDTO(malId: 5114, title: "Fullmetal Alchemist: Brotherhood", titleEnglish: "FMA: Brotherhood", status: "Finished Airing", episodes: 64)
        let second = store.addOrUpdate(from: dto2, status: .watching)

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(store.allAnime.count, 1)
        XCTAssertEqual(second.watchStatus, .watching)
        XCTAssertEqual(store.statusCounts[.planToWatch, default: 0], 0)
        XCTAssertEqual(store.statusCounts[.watching, default: 0], 1)
    }

    func testIncrementDecrementFinishReQueueAndDelete() throws {
        let dto = JikanAnimeDTO(malId: 1535, title: "Death Note", status: "Finished Airing", episodes: 2)
        let anime = store.addOrUpdate(from: dto, status: .planToWatch)

        store.incrementProgress(for: anime)
        XCTAssertEqual(anime.currentEpisodeProgress, 1)
        XCTAssertEqual(anime.watchStatus, .watching)
        XCTAssertEqual(store.statusCounts[.watching, default: 0], 1)

        store.incrementProgress(for: anime)
        XCTAssertEqual(anime.currentEpisodeProgress, 2)
        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertEqual(store.statusCounts[.watching, default: 0], 0)
        XCTAssertEqual(store.statusCounts[.completed, default: 0], 1)
        XCTAssertEqual(store.totalEpisodesWatched, 2)

        store.decrementProgress(for: anime)
        XCTAssertEqual(anime.currentEpisodeProgress, 1)
        XCTAssertEqual(store.totalEpisodesWatched, 1)

        store.setRating(9, for: anime)
        XCTAssertEqual(anime.userRating, 9)

        store.setCustomTitle("  L vs Kira  ", for: anime)
        XCTAssertEqual(anime.customTitleOverride, "L vs Kira")
        store.setCustomTitle("   ", for: anime)
        XCTAssertNil(anime.customTitleOverride)

        store.finish(anime)
        XCTAssertEqual(anime.watchStatus, .completed)
        XCTAssertEqual(anime.currentEpisodeProgress, 2)

        let prevAdded = anime.dateAdded
        Thread.sleep(forTimeInterval: 0.02)
        store.reQueue(anime)
        XCTAssertGreaterThan(anime.dateAdded, prevAdded)

        store.delete(anime)
        XCTAssertTrue(store.allAnime.isEmpty)
        XCTAssertNil(store.anime(forMalID: 1535))
        XCTAssertEqual(store.statusCounts[.completed, default: 0], 0)
    }

    func testDubbedLanguageMutationsAndMerging() {
        let dto = JikanAnimeDTO(malId: 21, title: "One Piece", status: "Currently Airing")
        let anime = store.addOrUpdate(from: dto, status: .watching, dubbedLanguages: ["Japanese"])

        // When English is newly discovered alongside Spanish, both merge in
        store.mergeDubbedLanguages(["Japanese", "English", "Spanish"], for: anime)
        XCTAssertTrue(anime.dubbedLanguages.contains("English"))
        XCTAssertTrue(anime.dubbedLanguages.contains("Spanish"))

        store.toggleDubbedLanguage(DubbedLanguage.resolve(from: "English"), for: anime)
        XCTAssertFalse(anime.dubbedLanguages.contains("English"))

        store.addCustomDubbedLanguage("Tamil", for: anime)
        XCTAssertTrue(anime.dubbedLanguages.contains("Tamil"))

        store.replaceDubbedLanguages(["Japanese"], for: anime)
        XCTAssertEqual(anime.dubbedLanguages, ["Japanese"])
    }

    func testCardSnapshotEquatableDetectsInPlaceModelMutations() {
        let dto = JikanAnimeDTO(malId: 30276, title: "One Punch Man", status: "Finished Airing", episodes: 12)
        let anime = store.addOrUpdate(from: dto, status: .watching)

        let snapBefore = anime.cardSnapshot(for: .english, isSelected: false)
        store.incrementProgress(for: anime)
        let snapAfterEpisode = anime.cardSnapshot(for: .english, isSelected: false)
        XCTAssertNotEqual(snapBefore, snapAfterEpisode)

        store.setWatchStatus(.completed, for: anime)
        let snapAfterStatus = anime.cardSnapshot(for: .english, isSelected: false)
        XCTAssertNotEqual(snapAfterEpisode, snapAfterStatus)

        let snapSelected = anime.cardSnapshot(for: .english, isSelected: true)
        XCTAssertNotEqual(snapAfterStatus, snapSelected)

        let discoverBefore = DiscoverCardSnapshot(dto: dto, trackedStatus: .watching, titleLanguagePreference: .english, isSelected: false)
        let discoverAfter = DiscoverCardSnapshot(dto: dto, trackedStatus: .completed, titleLanguagePreference: .english, isSelected: false)
        XCTAssertNotEqual(discoverBefore, discoverAfter)
    }
}
