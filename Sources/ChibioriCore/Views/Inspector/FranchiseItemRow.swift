import SwiftUI

@MainActor
struct FranchiseItemRow: View {
    @Environment(LibraryStore.self) private var libraryStore

    let item: RelatedAnimeItem
    let isCurrent: Bool
    let trackedMatch: TrackedAnime?
    let titlePreference: TitleLanguagePreference
    let onInspect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onInspect) {
                HStack(spacing: 12) {
                    posterThumbnail
                    metaDetails
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let tracked = trackedMatch {
                statusMenu(tracked: tracked)
                    .fixedSize()
            } else {
                trackMenu
                    .fixedSize()
            }

            Button(action: onInspect) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.5))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(rowBackground)
        .overlay(rowOverlay)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: some View {
        let fill: Color = isCurrent ? Color.yellow.opacity(0.06) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.025))
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
    }

    private var rowOverlay: some View {
        let stroke: Color = isCurrent ? Color.yellow.opacity(0.25) : (isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(stroke, lineWidth: 0.8)
    }

    private var posterThumbnail: some View {
        let strokeColor: Color = isCurrent ? Color.yellow.opacity(0.6) : Color.white.opacity(0.12)
        let strokeWidth: CGFloat = isCurrent ? 1.5 : 0.8

        return Group {
            if let cover = item.coverImageURL, !cover.isEmpty {
                CachedCoverImage(
                    malID: item.malID,
                    remoteURLString: cover,
                    cornerRadius: 6
                )
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: strokeWidth)
                )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 40, height: 56)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
    }

    private var metaDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: isCurrent ? "sparkles" : item.relationIcon)
                        .font(.system(size: 8))
                    Text(isCurrent ? "Current" : item.relationDisplayName)
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isCurrent ? Color.yellow.opacity(0.2) : item.badgeColor.opacity(0.18))
                .foregroundStyle(isCurrent ? Color.yellow : item.badgeColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isCurrent ? Color.yellow.opacity(0.5) : item.badgeColor.opacity(0.35), lineWidth: 0.8)
                )

                if let airing = item.airingStatus ?? trackedMatch?.airingStatus {
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
                } else if let st = item.status {
                    Text(st.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.displayTitle(for: titlePreference))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.95))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .help(item.displayTitle(for: titlePreference))

            let sub = item.metadataSubtitle
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusMenu(tracked: TrackedAnime) -> some View {
        Button {
            StatusMenuPresenter.shared.presentMenu(
                currentStatus: tracked.watchStatus,
                headerTitle: "CHANGE STATUS",
                includeRemoveAction: true,
                onRemove: {
                    withAnimation(.spring(response: 0.3)) {
                        libraryStore.delete(tracked)
                    }
                },
                onSelect: { status in
                    withAnimation(.spring(response: 0.3)) {
                        libraryStore.setWatchStatus(status, for: tracked)
                    }
                }
            )
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tracked.watchStatus.accentColor)
                    .frame(width: 6, height: 6)
                Text(tracked.watchStatus.displayName)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(tracked.watchStatus.accentColor.opacity(0.16))
            .foregroundStyle(tracked.watchStatus.accentColor)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(tracked.watchStatus.accentColor.opacity(0.4), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var trackMenu: some View {
        Button {
            StatusMenuPresenter.shared.presentMenu(
                currentStatus: nil,
                headerTitle: "ADD TO LIBRARY",
                onSelect: { status in
                    withAnimation(.spring(response: 0.3)) {
                        _ = libraryStore.addOrUpdate(from: item, status: status)
                    }
                }
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                Text("Track")
                    .font(.system(size: 10, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.accentColor.opacity(0.18))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
