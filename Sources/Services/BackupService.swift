import Foundation
import SwiftData

public struct ImportSummary: Sendable {
    public let totalParsed: Int
    public let insertedCount: Int
    public let updatedCount: Int
    public let errorsCount: Int
}

public final class BackupService: Sendable {
    public static let shared = BackupService()

    private init() {}

    // MARK: - Export
    public func generateExportData(from animeList: [TrackedAnime]) throws -> Data {
        let records = animeList.map { anime in
            AnimeBackupRecord(
                malID: anime.malID,
                title: anime.title,
                watchStatus: anime.watchStatusRaw,
                currentEpisodeProgress: anime.currentEpisodeProgress,
                userRating: anime.userRating,
                personalNotes: anime.personalNotes,
                dateAdded: AnimeBackupRecord.formatDate(anime.dateAdded) ?? AnimeBackupRecord.formatDate(Date())!,
                dateStarted: AnimeBackupRecord.formatDate(anime.dateStarted),
                dateCompleted: AnimeBackupRecord.formatDate(anime.dateCompleted),
                airingStatus: anime.airingStatusRaw,
                totalEpisodes: anime.totalEpisodes,
                malScore: anime.malScore,
                coverImageRemoteURL: anime.coverImageRemoteURL,
                englishTitle: anime.englishTitle,
                japaneseTitle: anime.japaneseTitle,
                customTitleOverride: anime.customTitleOverride,
                synopsis: anime.synopsis,
                seasonYear: anime.seasonYear,
                genres: anime.genres,
                broadcastDayRaw: anime.broadcastDayRaw,
                broadcastTimeUTC: anime.broadcastTimeUTC
            )
        }

        let root = AnimeBackupRoot(
            version: "1.0",
            exportedAt: AnimeBackupRecord.formatDate(Date()) ?? "",
            app: "Chibiori",
            records: records
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(root)
    }

    // MARK: - JSON Import
    @MainActor
    public func importBackup(data: Data, context: ModelContext) throws -> ImportSummary {
        let decoder = JSONDecoder()
        let root = try decoder.decode(AnimeBackupRoot.self, from: data)

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        let existingList = (try? context.fetch(fetchDescriptor)) ?? []
        var existingMap: [Int: TrackedAnime] = [:]
        for item in existingList {
            existingMap[item.malID] = item
        }

        var inserted = 0
        var updated = 0
        let errors = 0

        for record in root.records {
            let addedDate = AnimeBackupRecord.parseDate(record.dateAdded) ?? Date()
            let startedDate = AnimeBackupRecord.parseDate(record.dateStarted)
            let completedDate = AnimeBackupRecord.parseDate(record.dateCompleted)

            if let existing = existingMap[record.malID] {
                // Update existing record
                existing.title = record.title
                existing.watchStatusRaw = record.watchStatus
                existing.currentEpisodeProgress = record.currentEpisodeProgress
                existing.userRating = record.userRating
                existing.personalNotes = record.personalNotes
                existing.dateAdded = addedDate
                existing.dateStarted = startedDate
                existing.dateCompleted = completedDate
                existing.airingStatusRaw = record.airingStatus
                existing.totalEpisodes = record.totalEpisodes
                existing.malScore = record.malScore
                existing.coverImageRemoteURL = record.coverImageRemoteURL
                if let en = record.englishTitle { existing.englishTitle = en }
                if let jp = record.japaneseTitle { existing.japaneseTitle = jp }
                if let custom = record.customTitleOverride { existing.customTitleOverride = custom }
                if let syn = record.synopsis { existing.synopsis = syn }
                if let sy = record.seasonYear { existing.seasonYear = sy }
                if let g = record.genres { existing.genres = g }
                if let bd = record.broadcastDayRaw { existing.broadcastDayRaw = bd }
                if let bt = record.broadcastTimeUTC { existing.broadcastTimeUTC = bt }
                existing.statusLastUpdatedAt = Date()
                updated += 1
            } else {
                // Insert new record
                let newAnime = TrackedAnime(
                    malID: record.malID,
                    title: record.title,
                    synopsis: record.synopsis ?? "",
                    coverImageRemoteURL: record.coverImageRemoteURL,
                    airingStatusRaw: record.airingStatus,
                    englishTitle: record.englishTitle,
                    japaneseTitle: record.japaneseTitle,
                    customTitleOverride: record.customTitleOverride,
                    totalEpisodes: record.totalEpisodes,
                    broadcastDayRaw: record.broadcastDayRaw,
                    broadcastTimeUTC: record.broadcastTimeUTC,
                    malScore: record.malScore,
                    seasonYear: record.seasonYear,
                    genres: record.genres ?? []
                )
                newAnime.watchStatusRaw = record.watchStatus
                newAnime.currentEpisodeProgress = record.currentEpisodeProgress
                newAnime.userRating = record.userRating
                newAnime.personalNotes = record.personalNotes
                newAnime.dateAdded = addedDate
                newAnime.dateStarted = startedDate
                newAnime.dateCompleted = completedDate
                newAnime.statusLastUpdatedAt = Date()

                context.insert(newAnime)
                inserted += 1
            }
        }

        try context.save()

        return ImportSummary(
            totalParsed: root.records.count,
            insertedCount: inserted,
            updatedCount: updated,
            errorsCount: errors
        )
    }

    // MARK: - MyAnimeList (MAL) XML Import
    @MainActor
    public func importMALXML(data: Data, allowedStatuses: Set<WatchStatus>? = nil, context: ModelContext) throws -> ImportSummary {
        let parsedEntries = MALXMLParser.parse(data: data, allowedStatuses: allowedStatuses)

        let fetchDescriptor = FetchDescriptor<TrackedAnime>()
        let existingList = (try? context.fetch(fetchDescriptor)) ?? []
        var existingMap: [Int: TrackedAnime] = [:]
        for item in existingList {
            existingMap[item.malID] = item
        }

        var inserted = 0
        var updated = 0

        for entry in parsedEntries {
            if let existing = existingMap[entry.malID] {
                existing.title = entry.title
                existing.watchStatus = entry.status
                existing.currentEpisodeProgress = entry.watchedEpisodes
                if let total = entry.totalEpisodes {
                    existing.totalEpisodes = total
                }
                if let rating = entry.userRating {
                    existing.userRating = rating
                }
                if !entry.personalNotes.isEmpty {
                    existing.personalNotes = entry.personalNotes
                }
                if let airingRaw = entry.airingStatusRaw {
                    existing.airingStatusRaw = airingRaw
                }
                if let start = entry.seriesStart {
                    existing.seasonYear = start
                }
                existing.statusLastUpdatedAt = Date()
                if entry.status == .completed && existing.dateCompleted == nil {
                    existing.dateCompleted = Date()
                }
                updated += 1
            } else {
                let newAnime = TrackedAnime(
                    malID: entry.malID,
                    title: entry.title,
                    synopsis: "",
                    coverImageRemoteURL: "",
                    airingStatusRaw: entry.airingStatusRaw ?? (entry.status == .completed ? "Finished Airing" : "Currently Airing"),
                    totalEpisodes: entry.totalEpisodes,
                    seasonYear: entry.seriesStart
                )
                newAnime.watchStatus = entry.status
                newAnime.currentEpisodeProgress = entry.watchedEpisodes
                newAnime.userRating = entry.userRating
                newAnime.personalNotes = entry.personalNotes
                newAnime.dateAdded = Date()
                if entry.status == .completed {
                    newAnime.dateCompleted = Date()
                }
                newAnime.statusLastUpdatedAt = Date()

                context.insert(newAnime)
                inserted += 1
            }
        }

        try context.save()

        return ImportSummary(
            totalParsed: parsedEntries.count,
            insertedCount: inserted,
            updatedCount: updated,
            errorsCount: 0
        )
    }
}
