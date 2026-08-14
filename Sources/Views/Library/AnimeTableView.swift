import SwiftUI
import SwiftData

@MainActor
public struct AnimeTableView: View {
    let animes: [TrackedAnime]
    @Binding var selectedAnimeID: PersistentIdentifier?

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        return df
    }()

    public init(animes: [TrackedAnime], selectedAnimeID: Binding<PersistentIdentifier?>) {
        self.animes = animes
        self._selectedAnimeID = selectedAnimeID
    }

    public var body: some View {
        Table(animes, selection: $selectedAnimeID) {
            TableColumn("Anime") { anime in
                HStack(spacing: 10) {
                    CachedCoverImage(
                        malID: anime.malID,
                        remoteURLString: anime.coverImageRemoteURL,
                        localFilename: anime.coverImageFilename,
                        cornerRadius: 4,
                        shadowRadius: 1
                    )
                    .frame(width: 32, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(anime.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if let jp = anime.japaneseTitle, !jp.isEmpty {
                            Text(jp)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .width(min: 220, ideal: 300)

            TableColumn("Status") { anime in
                StatusPickerMenu(currentStatus: anime.watchStatus) { newStatus in
                    anime.setWatchStatus(newStatus)
                }
            }
            .width(min: 120, ideal: 140)

            TableColumn("Progress") { anime in
                HStack(spacing: 8) {
                    Text("\(anime.currentEpisodeProgress) / \(anime.totalEpisodes.map { String($0) } ?? "?")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 55, alignment: .trailing)

                    QuickEpisodeIncrementButton(
                        current: anime.currentEpisodeProgress,
                        total: anime.totalEpisodes
                    ) {
                        anime.incrementProgress()
                    }
                }
            }
            .width(min: 110, ideal: 130)

            TableColumn("Rating") { anime in
                if let rating = anime.userRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("\(rating)/10")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 65, ideal: 75)

            TableColumn("MAL Score") { anime in
                if let score = anime.malScore {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 75, ideal: 85)

            TableColumn("Airing") { anime in
                AiringStatusBadge(status: anime.airingStatus)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Date Added") { anime in
                Text(Self.dateFormatter.string(from: anime.dateAdded))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 95)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}
