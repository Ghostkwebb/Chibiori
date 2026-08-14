import SwiftUI

public struct AnimeCardView: View, Equatable {
    @Environment(NavigationState.self) private var navState
    @Bindable var anime: TrackedAnime
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    public static func == (lhs: AnimeCardView, rhs: AnimeCardView) -> Bool {
        lhs.anime.persistentModelID == rhs.anime.persistentModelID &&
        lhs.isSelected == rhs.isSelected &&
        lhs.anime.watchStatus == rhs.anime.watchStatus &&
        lhs.anime.currentEpisodeProgress == rhs.anime.currentEpisodeProgress &&
        lhs.anime.title == rhs.anime.title &&
        lhs.anime.englishTitle == rhs.anime.englishTitle &&
        lhs.anime.customTitleOverride == rhs.anime.customTitleOverride &&
        lhs.isHovered == rhs.isHovered
    }

    public init(anime: TrackedAnime, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.anime = anime
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster Art with Overlays
            ZStack(alignment: .bottom) {
                CachedCoverImage(
                    malID: anime.malID,
                    remoteURLString: anime.coverImageRemoteURL,
                    localFilename: anime.coverImageFilename,
                    cornerRadius: 10,
                    shadowRadius: isSelected ? 6 : (isHovered ? 8 : 3)
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(225 / 318, contentMode: .fit)

                // Top Score & Rating Badges
                VStack {
                    HStack {
                        // User rating star if rated
                        if let rating = anime.userRating {
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

                        if let score = anime.malScore {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.cyan)
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.70))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(6)
                    Spacer()
                }

                // Bottom Gradient Scrim & Episode Info
                VStack(spacing: 4) {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.80)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 52)
                }

                // Bottom Episode Info & Airing Badge
                VStack(spacing: 4) {
                    Spacer()
                    HStack {
                        AiringStatusBadge(status: anime.airingStatus)

                        Spacer()

                        // Episode count badge
                        Text("Ep \(anime.currentEpisodeProgress)/\(anime.totalEpisodes.map { String($0) } ?? "?")")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.70))
                            .clipShape(Capsule())
                    }
                    .padding(6)

                    // Linear Episode Progress Indicator (Zero-cost layout without GeometryReader)
                    if let total = anime.totalEpisodes, total > 0 {
                        let progress = min(1.0, max(0.0, CGFloat(anime.currentEpisodeProgress) / CGFloat(total)))
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
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Title & Controls
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.displayTitle(for: navState.titleLanguagePreference))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                    .foregroundStyle(.primary)

                HStack(alignment: .center) {
                    // Status Pill / Menu
                    StatusPickerMenu(currentStatus: anime.watchStatus) { newStatus in
                        withAnimation(.spring(response: 0.3)) {
                            anime.setWatchStatus(newStatus)
                        }
                    }

                    Spacer()

                    // Rapid +1 Button
                    QuickEpisodeIncrementButton(
                        current: anime.currentEpisodeProgress,
                        total: anime.totalEpisodes
                    ) {
                        anime.incrementProgress()
                    }
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 14, isHovered: isHovered, isSelected: isSelected)
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
                    anime.setWatchStatus(status)
                } label: {
                    Label("Move to \(status.displayName)", systemImage: status.systemImage)
                }
            }

            Divider()

            Button {
                anime.reQueue()
            } label: {
                Label("Re-queue (Move to Top)", systemImage: "arrow.clockwise")
            }

            Button {
                anime.incrementProgress()
            } label: {
                Label("+1 Episode", systemImage: "plus")
            }
        }
    }
}
