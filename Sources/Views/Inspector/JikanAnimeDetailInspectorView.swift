import SwiftUI
import SwiftData

@MainActor
public struct JikanAnimeDetailInspectorView: View {
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext
    let dto: JikanAnimeDTO
    let onAddedToLibrary: (TrackedAnime) -> Void

    @State private var relatedAnime: [RelatedAnimeItem] = []
    @State private var loadedDubbedLanguages: [DubbedLanguage] = []

    public init(dto: JikanAnimeDTO, onAddedToLibrary: @escaping (TrackedAnime) -> Void) {
        self.dto = dto
        self.onAddedToLibrary = onAddedToLibrary
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Large Poster & Info Showcase Header
                headerSection

                // Related Seasons (Prequels / Sequels)
                if !relatedAnime.isEmpty {
                    RelatedSeasonsCardView(
                        relatedAnime: relatedAnime,
                        currentMalID: dto.malId,
                        currentTitle: dto.title,
                        currentEnglishTitle: dto.titleEnglish
                    )
                    .padding(14)
                    .glassCard(cornerRadius: 14)
                }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: dto.malId) {
            async let rels = AnimeRelationsService.shared.fetchRelations(for: dto.malId, title: dto.title)
            async let dubs = DubbedLanguageService.shared.fetchDubbedLanguages(malId: dto.malId)
            relatedAnime = await rels
            loadedDubbedLanguages = await dubs
        }
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
                Text(dto.displayTitle(for: navState.titleLanguagePreference))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)


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

                if let dates = dto.airingDatesDisplay {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .padding(.top, 1)
                        Text(dates)
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
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

                dubbedLanguagesHeaderRow
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
                        englishTitle: dto.titleEnglish,
                        japaneseTitle: dto.titleJapanese,
                        totalEpisodes: dto.episodes,
                        broadcastDayRaw: dto.broadcast?.day,
                        broadcastTimeUTC: dto.broadcast?.time,
                        malScore: dto.score,
                        seasonYear: dto.startDateFormatted ?? dto.seasonYearFormatted,
                        airingEndDate: dto.airingEndDateFormatted,
                        genres: dto.genreNames,
                        dubbedLanguages: loadedDubbedLanguages.map { $0.name }
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
                if let release = dto.startDateFormatted ?? dto.seasonYearFormatted {
                    metadataRow(label: "Release Date", value: release)
                }
                if let ended = dto.airingEndDateFormatted, AiringStatus.from(raw: dto.status) == .finishedAiring {
                    metadataRow(label: "Ended", value: ended)
                }
                if let episodes = dto.episodes {
                    metadataRow(label: "Total Episodes", value: "\(episodes)")
                }
                if let studios = dto.studios, !studios.isEmpty {
                    metadataRow(label: "Studios", value: studios.map { $0.name }.joined(separator: ", "))
                }
                if let genres = dto.genres, !genres.isEmpty {
                    metadataRow(label: "Genres", value: genres.map { $0.name }.joined(separator: ", "))
                }
                if !loadedDubbedLanguages.isEmpty {
                    metadataRow(label: "Dubbed In", value: loadedDubbedLanguages.map { $0.isNativeAudio ? "\($0.name) (Original)" : $0.name }.joined(separator: ", "))
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

    // MARK: - Dubbed Languages Header Row
    private var dubbedLanguagesHeaderRow: some View {
        let langs = !loadedDubbedLanguages.isEmpty ? loadedDubbedLanguages : dto.resolvedDubbedLanguages
        return HStack(alignment: .top, spacing: 5) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            WrappingFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(langs) { lang in
                    dubPill(lang: lang)
                }
            }
        }
        .padding(.top, 1)
    }

    private func dubPill(lang: DubbedLanguage) -> some View {
        HStack(spacing: 2) {
            Text(lang.code)
                .font(.system(size: 9.5, weight: lang.isNativeAudio ? .bold : .medium, design: .rounded))
            if lang.isNativeAudio {
                Circle()
                    .fill(Color.purple.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            lang.isNativeAudio ?
            Color.purple.opacity(0.25) :
            Color.white.opacity(0.1)
        )
        .foregroundStyle(lang.isNativeAudio ? Color.purple.opacity(0.95) : Color.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                lang.isNativeAudio ? Color.purple.opacity(0.4) : Color.white.opacity(0.12),
                lineWidth: 0.6
            )
        )
        .help(lang.tooltipText)
    }
}
