import SwiftUI
import SwiftData

@MainActor
public struct RelatedSeasonsCardView: View {
    @Environment(NavigationState.self) private var navState
    @Query private var allTrackedAnime: [TrackedAnime]

    let relatedAnime: [RelatedAnimeItem]
    let currentMalID: Int
    let currentTitle: String
    let currentEnglishTitle: String?

    @State private var showFranchiseHub = false

    public init(
        relatedAnime: [RelatedAnimeItem],
        currentMalID: Int = 0,
        currentTitle: String = "",
        currentEnglishTitle: String? = nil
    ) {
        self.relatedAnime = relatedAnime
        self.currentMalID = currentMalID
        self.currentTitle = currentTitle
        self.currentEnglishTitle = currentEnglishTitle
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

                if !currentTitle.isEmpty || currentMalID > 0 {
                    Button {
                        showFranchiseHub = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("Explore")
                                .font(.system(size: 9.5, weight: .semibold))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.18))
                        .foregroundStyle(Color.purple)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.purple.opacity(0.35), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("View full franchise releases and spin-offs")
                }

                Text("\(relatedAnime.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }

            // List of related anime seasons
            let trackedByID: [Int: TrackedAnime] = Dictionary(
                allTrackedAnime.map { ($0.malID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            VStack(spacing: 8) {
                ForEach(relatedAnime) { rel in
                    let match = findMatchingTracked(for: rel, map: trackedByID)
                    RelatedAnimeRowView(
                        item: rel,
                        trackedMatch: match,
                        titleLanguagePreference: navState.titleLanguagePreference
                    ) {
                        if let match {
                            navState.navigateTo(tracked: match)
                        } else {
                            navState.navigateTo(dto: rel.asJikanDTO)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFranchiseHub) {
            FranchiseHubSheetView(
                currentMalID: currentMalID,
                currentTitle: currentTitle,
                currentEnglishTitle: currentEnglishTitle
            )
        }
    }

    private func findMatchingTracked(for item: RelatedAnimeItem, map: [Int: TrackedAnime]) -> TrackedAnime? {
        if item.malID > 0, let match = map[item.malID] {
            return match
        }
        let itemTitle = item.title.lowercased()
        let itemEn = item.englishTitle?.lowercased()
        return allTrackedAnime.first { tracked in
            tracked.title.lowercased() == itemTitle ||
            (itemEn != nil && tracked.englishTitle?.lowercased() == itemEn)
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

    private var resolvedAiringStatus: AiringStatus? {
        if let airing = item.airingStatus {
            return airing
        }
        return trackedMatch?.airingStatus
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Cover Thumbnail with instant memory cache & downsampler
                if let cover = item.coverImageURL, !cover.isEmpty {
                    CachedCoverImage(
                        malID: item.malID,
                        remoteURLString: cover,
                        cornerRadius: 6
                    )
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
                    HStack(spacing: 4) {
                        // Relation Badge
                        HStack(spacing: 3) {
                            Image(systemName: item.relationIcon)
                                .font(.system(size: 8))
                            Text(item.relationDisplayName)
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(item.badgeColor.opacity(0.18))
                        .foregroundStyle(item.badgeColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(item.badgeColor.opacity(0.35), lineWidth: 0.8)
                        )

                        // Airing Status Badge (Airing / Finished / Upcoming)
                        if let airing = resolvedAiringStatus {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(airing.dotColor)
                                    .frame(width: 4.5, height: 4.5)
                                Text(airing.shortDisplayName)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(airing.dotColor.opacity(0.16))
                            .foregroundStyle(airing.dotColor)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(airing.dotColor.opacity(0.35), lineWidth: 0.8)
                            )
                        } else if let raw = item.status, !raw.isEmpty {
                            Text(raw.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }

                        // Library Status Badge if in library (Plan to Watch / Watching / Completed, etc.)
                        if let tracked = trackedMatch {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(tracked.watchStatus.accentColor)
                                    .frame(width: 4.5, height: 4.5)
                                Text(tracked.watchStatus.displayName)
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tracked.watchStatus.accentColor.opacity(0.15))
                            .foregroundStyle(tracked.watchStatus.accentColor)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(tracked.watchStatus.accentColor.opacity(0.3), lineWidth: 0.8)
                            )
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
