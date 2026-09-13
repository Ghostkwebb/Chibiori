import SwiftUI
import SwiftData

@MainActor
public struct RelatedSeasonsCardView: View {
    @Environment(NavigationState.self) private var navState
    @Query private var allTrackedAnime: [TrackedAnime]

    let relatedAnime: [RelatedAnimeItem]

    public init(relatedAnime: [RelatedAnimeItem]) {
        self.relatedAnime = relatedAnime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.purple)

                Text("RELATED SEASONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(relatedAnime.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }

            // List of related anime seasons
            VStack(spacing: 8) {
                ForEach(relatedAnime) { rel in
                    RelatedAnimeRowView(
                        item: rel,
                        trackedMatch: allTrackedAnime.first(where: { $0.malID == rel.malID }),
                        titleLanguagePreference: navState.titleLanguagePreference
                    ) {
                        if let matching = allTrackedAnime.first(where: { $0.malID == rel.malID }) {
                            navState.selectTracked(matching.persistentModelID)
                        } else {
                            navState.selectDTO(rel.asJikanDTO)
                        }
                    }
                }
            }
        }
    }
}

@MainActor
struct RelatedAnimeRowView: View {
    let item: RelatedAnimeItem
    let trackedMatch: TrackedAnime?
    let titleLanguagePreference: TitleLanguagePreference
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Cover Thumbnail
                if let cover = item.coverImageURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.white.opacity(0.06)
                        }
                    }
                    .frame(width: 38, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 38, height: 52)
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        )
                }

                // Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        // Relation Badge
                        HStack(spacing: 3) {
                            Image(systemName: item.relationIcon)
                                .font(.system(size: 8))
                            Text(item.relationDisplayName)
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.badgeColor.opacity(0.18))
                        .foregroundStyle(item.badgeColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(item.badgeColor.opacity(0.35), lineWidth: 0.8)
                        )

                        // Library Status Badge if in library
                        if let tracked = trackedMatch {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(tracked.watchStatus.accentColor)
                                    .frame(width: 5, height: 5)
                                Text(tracked.watchStatus.displayName)
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tracked.watchStatus.accentColor.opacity(0.15))
                            .foregroundStyle(tracked.watchStatus.accentColor)
                            .clipShape(Capsule())
                        }
                    }

                    Text(item.displayTitle(for: titleLanguagePreference))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    let sub = item.metadataSubtitle
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.6))
                    .offset(x: isHovered ? 2 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.07), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
