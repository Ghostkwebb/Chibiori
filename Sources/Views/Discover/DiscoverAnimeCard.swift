import SwiftUI
import SwiftData

public struct DiscoverAnimeCard: View, Equatable {
    @Environment(NavigationState.self) private var navState
    let dto: JikanAnimeDTO
    let existingTracked: TrackedAnime?
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    let onAddToLibrary: (WatchStatus) -> Void

    @State private var isHovered = false

    public static func == (lhs: DiscoverAnimeCard, rhs: DiscoverAnimeCard) -> Bool {
        lhs.dto.malId == rhs.dto.malId &&
        lhs.isSelected == rhs.isSelected &&
        lhs.existingTracked?.watchStatus == rhs.existingTracked?.watchStatus &&
        lhs.dto.title == rhs.dto.title &&
        lhs.dto.titleEnglish == rhs.dto.titleEnglish &&
        lhs.isHovered == rhs.isHovered
    }

    public init(
        dto: JikanAnimeDTO,
        existingTracked: TrackedAnime?,
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil,
        onAddToLibrary: @escaping (WatchStatus) -> Void
    ) {
        self.dto = dto
        self.existingTracked = existingTracked
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onAddToLibrary = onAddToLibrary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster Art
            ZStack(alignment: .bottom) {
                CachedCoverImage(
                    malID: dto.malId,
                    remoteURLString: dto.coverImageURL,
                    cornerRadius: 10,
                    shadowRadius: isSelected ? 6 : (isHovered ? 8 : 3)
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(225 / 318, contentMode: .fit)

                // Top Score Badge
                VStack {
                    HStack {
                        Spacer()
                        if let score = dto.score {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
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

                // Bottom Scrim & Badges
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
                        AiringStatusBadge(status: AiringStatus.from(raw: dto.status))
                        Spacer()
                        if let episodes = dto.episodes {
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

            // Title & Information
            VStack(alignment: .leading, spacing: 5) {
                Text(dto.displayTitle(for: navState.titleLanguagePreference))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                    .foregroundStyle(.primary)

                if let seasonYear = dto.seasonYearFormatted {
                    Text(seasonYear)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Add or In-Library status
                if let tracked = existingTracked {
                    StatusPickerMenu(currentStatus: tracked.watchStatus) { newStatus in
                        withAnimation(.spring(response: 0.3)) {
                            tracked.setWatchStatus(newStatus)
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
        .glassCard(cornerRadius: 14, isHovered: isHovered, isSelected: isSelected)
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
