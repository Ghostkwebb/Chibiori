import SwiftUI
import SwiftData

/// Value-type snapshot of a `TrackedAnime` card so SwiftUI `.equatable()` diffing
/// never skips re-renders when in-place `@Model` properties mutate.
public struct AnimeCardSnapshot: Equatable, Sendable {
    public let persistentID: PersistentIdentifier
    public let malID: Int
    public let displayTitle: String
    public let coverImageRemoteURL: String
    public let coverImageFilename: String?
    public let watchStatus: WatchStatus
    public let currentEpisodeProgress: Int
    public let totalEpisodes: Int?
    public let malScore: Double?
    public let scoreSource: ScoreSource
    public let userRating: Int?
    public let airingStatus: AiringStatus?
    public let isSelected: Bool

    public init(
        persistentID: PersistentIdentifier,
        malID: Int,
        displayTitle: String,
        coverImageRemoteURL: String,
        coverImageFilename: String?,
        watchStatus: WatchStatus,
        currentEpisodeProgress: Int,
        totalEpisodes: Int?,
        malScore: Double?,
        scoreSource: ScoreSource = .mal,
        userRating: Int?,
        airingStatus: AiringStatus?,
        isSelected: Bool
    ) {
        self.persistentID = persistentID
        self.malID = malID
        self.displayTitle = displayTitle
        self.coverImageRemoteURL = coverImageRemoteURL
        self.coverImageFilename = coverImageFilename
        self.watchStatus = watchStatus
        self.currentEpisodeProgress = currentEpisodeProgress
        self.totalEpisodes = totalEpisodes
        self.malScore = malScore
        self.scoreSource = scoreSource
        self.userRating = userRating
        self.airingStatus = airingStatus
        self.isSelected = isSelected
    }
}

extension TrackedAnime {
    public func cardSnapshot(
        for preference: TitleLanguagePreference,
        isSelected: Bool,
        scoreDisplay: (source: ScoreSource, score: Double)? = nil
    ) -> AnimeCardSnapshot {
        AnimeCardSnapshot(
            persistentID: persistentModelID,
            malID: malID,
            displayTitle: displayTitle(for: preference),
            coverImageRemoteURL: coverImageRemoteURL,
            coverImageFilename: coverImageFilename,
            watchStatus: watchStatus,
            currentEpisodeProgress: currentEpisodeProgress,
            totalEpisodes: totalEpisodes,
            malScore: scoreDisplay?.score ?? malScore,
            scoreSource: scoreDisplay?.source ?? .aniList,
            userRating: userRating,
            airingStatus: airingStatus,
            isSelected: isSelected
        )
    }
}

public struct AnimeCardView: View, Equatable {
    let snapshot: AnimeCardSnapshot
    let onSelect: () -> Void
    let onStatusChange: (WatchStatus) -> Void
    let onReQueue: () -> Void
    let onIncrementProgress: () -> Void

    @State private var isHovered = false

    public static func == (lhs: AnimeCardView, rhs: AnimeCardView) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    public init(
        snapshot: AnimeCardSnapshot,
        onSelect: @escaping () -> Void,
        onStatusChange: @escaping (WatchStatus) -> Void = { _ in },
        onReQueue: @escaping () -> Void = {},
        onIncrementProgress: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.onSelect = onSelect
        self.onStatusChange = onStatusChange
        self.onReQueue = onReQueue
        self.onIncrementProgress = onIncrementProgress
    }

    public init(
        anime: TrackedAnime,
        titleLanguagePreference: TitleLanguagePreference = .english,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onStatusChange: @escaping (WatchStatus) -> Void = { _ in },
        onReQueue: @escaping () -> Void = {},
        onIncrementProgress: @escaping () -> Void = {}
    ) {
        self.snapshot = anime.cardSnapshot(for: titleLanguagePreference, isSelected: isSelected)
        self.onSelect = onSelect
        self.onStatusChange = onStatusChange
        self.onReQueue = onReQueue
        self.onIncrementProgress = onIncrementProgress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedCoverImage(
                malID: snapshot.malID,
                remoteURLString: snapshot.coverImageRemoteURL,
                localFilename: snapshot.coverImageFilename,
                cornerRadius: 10,
                shadowRadius: 0
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(225 / 318, contentMode: .fit)
            .overlay(alignment: .top) {
                topBadges
            }
            .overlay(alignment: .bottom) {
                bottomBadgesAndProgress
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.displayTitle)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                    .foregroundStyle(.primary)

                HStack(alignment: .center) {
                    StatusPickerMenu(currentStatus: snapshot.watchStatus) { newStatus in
                        withAnimation(.spring(response: 0.3)) {
                            onStatusChange(newStatus)
                        }
                    }

                    Spacer()

                    QuickEpisodeIncrementButton(
                        current: snapshot.currentEpisodeProgress,
                        total: snapshot.totalEpisodes
                    ) {
                        onIncrementProgress()
                    }
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 14, isHovered: isHovered, isSelected: snapshot.isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .contextMenu {
            ForEach(WatchStatus.allCases) { status in
                Button {
                    onStatusChange(status)
                } label: {
                    Label("Move to \(status.displayName)", systemImage: status.systemImage)
                }
            }

            Divider()

            Button {
                onReQueue()
            } label: {
                Label("Re-queue (Move to Top)", systemImage: "arrow.clockwise")
            }

            Button {
                onIncrementProgress()
            } label: {
                Label("+1 Episode", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var topBadges: some View {
        HStack {
            if let rating = snapshot.userRating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                    Text("\(rating)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.70))
                .clipShape(Capsule())
            }

            Spacer()

            if let score = snapshot.malScore, score > 0 {
                SiteScoreCardPill(source: snapshot.scoreSource, score: score)
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var bottomBadgesAndProgress: some View {
        VStack(spacing: 4) {
            HStack {
                AiringStatusBadge(status: snapshot.airingStatus)

                Spacer()

                Text("Ep \(snapshot.currentEpisodeProgress)/\(snapshot.totalEpisodes.map { String($0) } ?? "?")")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.70))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let total = snapshot.totalEpisodes, total > 0 {
                let progress = min(1.0, max(0.0, CGFloat(snapshot.currentEpisodeProgress) / CGFloat(total)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 3)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: progress, y: 1.0, anchor: .leading)
                        .frame(height: 3)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
                .background(Color.black.opacity(0.85))
            }
        }
    }
}
