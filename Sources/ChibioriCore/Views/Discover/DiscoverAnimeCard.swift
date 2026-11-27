import SwiftUI

/// Value-type snapshot for `DiscoverAnimeCard` so `.equatable()` accurately reflects status and selection updates.
public struct DiscoverCardSnapshot: Equatable, Sendable {
    public let malID: Int
    public let displayTitle: String
    public let coverImageURL: String
    public let score: Double?
    public let scoreSource: ScoreSource
    public let airingStatus: AiringStatus?
    public let episodes: Int?
    public let seasonYearFormatted: String?
    public let trackedStatus: WatchStatus?
    public let isSelected: Bool

    public init(
        malID: Int,
        displayTitle: String,
        coverImageURL: String,
        score: Double?,
        scoreSource: ScoreSource = .aniList,
        airingStatus: AiringStatus?,
        episodes: Int?,
        seasonYearFormatted: String?,
        trackedStatus: WatchStatus?,
        isSelected: Bool
    ) {
        self.malID = malID
        self.displayTitle = displayTitle
        self.coverImageURL = coverImageURL
        self.score = score
        self.scoreSource = scoreSource
        self.airingStatus = airingStatus
        self.episodes = episodes
        self.seasonYearFormatted = seasonYearFormatted
        self.trackedStatus = trackedStatus
        self.isSelected = isSelected
    }

    public init(
        dto: JikanAnimeDTO,
        trackedStatus: WatchStatus?,
        titleLanguagePreference: TitleLanguagePreference,
        isSelected: Bool,
        scoreDisplay: (source: ScoreSource, score: Double)? = nil
    ) {
        self.malID = dto.malId
        self.displayTitle = dto.displayTitle(for: titleLanguagePreference)
        self.coverImageURL = dto.coverImageURL
        self.score = scoreDisplay?.score ?? dto.score
        self.scoreSource = scoreDisplay?.source ?? .aniList
        self.airingStatus = AiringStatus.from(raw: dto.status)
        self.episodes = dto.episodes
        self.seasonYearFormatted = dto.seasonYearFormatted
        self.trackedStatus = trackedStatus
        self.isSelected = isSelected
    }
}

public struct DiscoverAnimeCard: View, Equatable {
    let snapshot: DiscoverCardSnapshot
    var onSelect: (() -> Void)? = nil
    let onAddToLibrary: (WatchStatus) -> Void
    var onStatusChange: ((WatchStatus) -> Void)? = nil

    @State private var isHovered = false

    public static func == (lhs: DiscoverAnimeCard, rhs: DiscoverAnimeCard) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    public init(
        snapshot: DiscoverCardSnapshot,
        onSelect: (() -> Void)? = nil,
        onStatusChange: ((WatchStatus) -> Void)? = nil,
        onAddToLibrary: @escaping (WatchStatus) -> Void
    ) {
        self.snapshot = snapshot
        self.onSelect = onSelect
        self.onStatusChange = onStatusChange
        self.onAddToLibrary = onAddToLibrary
    }

    public init(
        dto: JikanAnimeDTO,
        existingTracked: TrackedAnime?,
        titleLanguagePreference: TitleLanguagePreference = .english,
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil,
        onStatusChange: ((TrackedAnime, WatchStatus) -> Void)? = nil,
        onAddToLibrary: @escaping (WatchStatus) -> Void
    ) {
        self.snapshot = DiscoverCardSnapshot(
            dto: dto,
            trackedStatus: existingTracked?.watchStatus,
            titleLanguagePreference: titleLanguagePreference,
            isSelected: isSelected
        )
        self.onSelect = onSelect
        if let existingTracked, let onStatusChange {
            self.onStatusChange = { newStatus in onStatusChange(existingTracked, newStatus) }
        } else {
            self.onStatusChange = nil
        }
        self.onAddToLibrary = onAddToLibrary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                CachedCoverImage(
                    malID: snapshot.malID,
                    remoteURLString: snapshot.coverImageURL,
                    cornerRadius: 10,
                    shadowRadius: 0
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(225 / 318, contentMode: .fit)

                VStack {
                    HStack {
                        Spacer()
                        if let score = snapshot.score, score > 0 {
                            SiteScoreCardPill(source: snapshot.scoreSource, score: score)
                        }
                    }
                    .padding(6)
                    Spacer()
                }

                VStack(spacing: 4) {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.80)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 44)
                }

                VStack {
                    Spacer()
                    HStack {
                        AiringStatusBadge(status: snapshot.airingStatus)
                        Spacer()
                        if let episodes = snapshot.episodes {
                            Text("\(episodes) eps")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.70))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.displayTitle)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                    .foregroundStyle(.primary)

                if let seasonYear = snapshot.seasonYearFormatted {
                    Text(seasonYear)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let trackedStatus = snapshot.trackedStatus {
                    StatusPickerMenu(currentStatus: trackedStatus) { newStatus in
                        withAnimation(.spring(response: 0.3)) {
                            onStatusChange?(newStatus)
                        }
                    }
                } else {
                    ColorCodedStatusPickerMenu(
                        currentStatus: nil,
                        title: "Track Anime"
                    ) { status in
                        onAddToLibrary(status)
                    }
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 14, isHovered: isHovered, isSelected: snapshot.isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
    }
}
