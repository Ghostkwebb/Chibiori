import SwiftUI
import SwiftData

@MainActor
public struct JikanAnimeDetailInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    let dto: JikanAnimeDTO
    let onAddedToLibrary: (TrackedAnime) -> Void

    public init(dto: JikanAnimeDTO, onAddedToLibrary: @escaping (TrackedAnime) -> Void) {
        self.dto = dto
        self.onAddedToLibrary = onAddedToLibrary
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Large Poster & Info Showcase Header
                headerSection

                // Track Anime Action Card
                trackActionSection
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                // Synopsis Card
                if let synopsis = dto.synopsis, !synopsis.isEmpty {
                    synopsisSection(synopsis: synopsis)
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                }

                // Details & Broadcast Info
                metadataSection
                    .padding(14)
                    .glassCard(cornerRadius: 14)
            }
            .padding(12)
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 440)
    }

    // MARK: - Header & Large Poster Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            // Large Poster Art
            CachedCoverImage(
                malID: dto.malId,
                remoteURLString: dto.coverImageURL,
                cornerRadius: 12,
                shadowRadius: 8
            )
            .frame(width: 120, height: 170)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

            // Title & Highlights
            VStack(alignment: .leading, spacing: 6) {
                Text(dto.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let jp = dto.titleJapanese, !jp.isEmpty {
                    Text(jp)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Score & Airing Status Badges
                HStack(spacing: 6) {
                    if let score = dto.score {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                    }

                    AiringStatusBadge(status: AiringStatus.from(raw: dto.status))
                }
                .padding(.top, 2)

                if let seasonYear = dto.seasonYearFormatted {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(seasonYear)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }

                if let episodes = dto.episodes {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                        Text("\(episodes) Episodes")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Track Action Section
    private var trackActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD TO LIBRARY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ColorCodedStatusPickerMenu(
                currentStatus: nil,
                title: "Track Anime in Library"
            ) { status in
                withAnimation(.spring(response: 0.3)) {
                    let anime = TrackedAnime(
                        malID: dto.malId,
                        title: dto.title,
                        synopsis: dto.synopsis ?? "",
                        coverImageRemoteURL: dto.coverImageURL,
                        airingStatusRaw: dto.status ?? "Finished Airing",
                        japaneseTitle: dto.titleJapanese,
                        totalEpisodes: dto.episodes,
                        broadcastDayRaw: dto.broadcast?.day
                    )
                    anime.watchStatus = status
                    modelContext.insert(anime)
                    try? modelContext.save()
                    onAddedToLibrary(anime)
                }
            }
        }
    }

    // MARK: - Synopsis Section
    private func synopsisSection(synopsis: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNOPSIS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(synopsis)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANIME DETAILS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                if let episodes = dto.episodes {
                    metadataRow(label: "Total Episodes", value: "\(episodes)")
                }
                if let studios = dto.studios, !studios.isEmpty {
                    metadataRow(label: "Studios", value: studios.map { $0.name }.joined(separator: ", "))
                }
                if let genres = dto.genres, !genres.isEmpty {
                    metadataRow(label: "Genres", value: genres.map { $0.name }.joined(separator: ", "))
                }
                if let broadcast = dto.broadcast?.string {
                    metadataRow(label: "Broadcast", value: broadcast)
                }
                if let rating = dto.rating {
                    metadataRow(label: "Age Rating", value: rating)
                }
                metadataRow(label: "MyAnimeList ID", value: "\(dto.malId)")
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
