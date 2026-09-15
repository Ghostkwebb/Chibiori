import SwiftUI
import SwiftData

public enum FranchiseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case main = "Main Story"
    case movies = "Movies"
    case ovas = "OVAs & Specials"

    public var id: String { rawValue }
}

@MainActor
public struct FranchiseHubSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationState.self) private var navState
    @Query private var allTrackedAnime: [TrackedAnime]

    let currentMalID: Int
    let currentTitle: String
    let currentEnglishTitle: String?

    @State private var franchiseItems: [RelatedAnimeItem] = []
    @State private var isLoading = true
    @State private var selectedFilter: FranchiseFilter = .all
    @State private var searchText = ""

    public init(
        currentMalID: Int,
        currentTitle: String,
        currentEnglishTitle: String? = nil
    ) {
        self.currentMalID = currentMalID
        self.currentTitle = currentTitle
        self.currentEnglishTitle = currentEnglishTitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .opacity(0.4)

            // Search & Filter Tabs
            controlsSection
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.3)

            // Content Area
            if isLoading && franchiseItems.isEmpty {
                loadingView
            } else if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsListView
            }
        }
        .frame(minWidth: 680, idealWidth: 740, maxWidth: 880, minHeight: 560, idealHeight: 620, maxHeight: 820)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.85)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        )
        .task {
            await loadFranchise()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.4), Color.indigo.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise Hub")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(currentTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Refresh Button
            Button {
                Task {
                    await loadFranchise(forceRefresh: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("Refresh franchise media from network")

            // Done Button
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Filter & Search Controls
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search franchise media...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )

            // Filter Tabs
            HStack(spacing: 8) {
                ForEach(FranchiseFilter.allCases) { filter in
                    let count = count(for: filter)
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: selectedFilter == filter ? .bold : .medium))
                            Text("\(count)")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    selectedFilter == filter
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedFilter == filter
                            ? Color.purple.opacity(0.35)
                            : Color.white.opacity(0.05)
                        )
                        .foregroundStyle(selectedFilter == filter ? Color.white : Color.secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedFilter == filter ? Color.purple.opacity(0.6) : Color.white.opacity(0.1),
                                    lineWidth: 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
    }

    private var trackedLookup: [Int: TrackedAnime] {
        Dictionary(allTrackedAnime.map { ($0.malID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - List View
    private var itemsListView: some View {
        let lookup = trackedLookup
        return ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredItems) { item in
                    let match = lookup[item.malID]
                    FranchiseItemRow(
                        item: item,
                        isCurrent: item.malID == currentMalID,
                        trackedMatch: match,
                        titlePreference: navState.titleLanguagePreference,
                        onInspect: {
                            if let match {
                                navState.selectTracked(match.persistentModelID)
                            } else {
                                navState.selectDTO(item.asJikanDTO)
                            }
                            dismiss()
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .smooth120HzScroll()
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Discovering franchise media...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text("No Media Found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("No entries match \"\(searchText)\" in this category.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No related franchise entries are available for this section.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
    private func loadFranchise(forceRefresh: Bool = false) async {
        isLoading = true
        let items = await AnimeRelationsService.shared.fetchFullFranchise(
            malID: currentMalID,
            title: currentTitle,
            englishTitle: currentEnglishTitle,
            allLibrary: allTrackedAnime,
            forceRefresh: forceRefresh
        )
        self.franchiseItems = items
        self.isLoading = false
    }

    private var filteredItems: [RelatedAnimeItem] {
        var list = franchiseItems
        switch selectedFilter {
        case .all:
            break
        case .main:
            list = list.filter { item in
                let t = item.relationType.uppercased()
                return t == "CURRENT" || t == "PREQUEL" || t == "SEQUEL" || t == "MAIN_STORY" || t == "SEASON" || t == "PARENT" || item.format == "TV"
            }
        case .movies:
            list = list.filter { item in
                item.relationType.uppercased() == "MOVIE" || item.format == "MOVIE"
            }
        case .ovas:
            list = list.filter { item in
                let t = item.relationType.uppercased()
                let f = item.format?.uppercased() ?? ""
                return t == "OVA" || t == "ONA" || t == "SPECIAL" || t == "SIDE_STORY" || t == "SPIN_OFF" || f == "OVA" || f == "ONA" || f == "SPECIAL"
            }
        }

        let cleanQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanQuery.isEmpty {
            list = list.filter { item in
                item.title.lowercased().contains(cleanQuery) ||
                (item.englishTitle?.lowercased().contains(cleanQuery) ?? false) ||
                item.relationDisplayName.lowercased().contains(cleanQuery) ||
                (item.format?.lowercased().contains(cleanQuery) ?? false)
            }
        }

        return list
    }

    private func count(for filter: FranchiseFilter) -> Int {
        switch filter {
        case .all:
            return franchiseItems.count
        case .main:
            return franchiseItems.filter { item in
                let t = item.relationType.uppercased()
                return t == "CURRENT" || t == "PREQUEL" || t == "SEQUEL" || t == "MAIN_STORY" || t == "SEASON" || t == "PARENT" || item.format == "TV"
            }.count
        case .movies:
            return franchiseItems.filter { item in
                item.relationType.uppercased() == "MOVIE" || item.format == "MOVIE"
            }.count
        case .ovas:
            return franchiseItems.filter { item in
                let t = item.relationType.uppercased()
                let f = item.format?.uppercased() ?? ""
                return t == "OVA" || t == "ONA" || t == "SPECIAL" || t == "SIDE_STORY" || t == "SPIN_OFF" || f == "OVA" || f == "ONA" || f == "SPECIAL"
            }.count
        }
    }
}

// MARK: - Franchise Item Row
@MainActor
struct FranchiseItemRow: View {
    @Environment(\.modelContext) private var modelContext

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
            if let cover = item.coverImageURL, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.06)
                    }
                }
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

                if let st = item.status {
                    Text(st.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 9))
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
        Menu {
            Section("CHANGE STATUS") {
                ForEach(WatchStatus.allCases) { status in
                    Button {
                        updateStatus(for: tracked, to: status)
                    } label: {
                        HStack {
                            Image(nsImage: status.coloredMenuIcon)
                            Text(status.displayName)
                            if tracked.watchStatus == status {
                                Text("✓")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                removeFromLibrary(tracked: tracked)
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var trackMenu: some View {
        Menu {
            Section("ADD TO LIBRARY") {
                ForEach(WatchStatus.allCases) { status in
                    Button {
                        trackAnime(with: status)
                    } label: {
                        HStack {
                            Image(nsImage: status.coloredMenuIcon)
                            Text(status.displayName)
                        }
                    }
                }
            }
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func trackAnime(with status: WatchStatus) {
        withAnimation(.spring(response: 0.3)) {
            let yearStr: String? = item.seasonYear != nil ? "\(item.seasonYear!)" : nil
            let anime = TrackedAnime(
                malID: item.malID,
                title: item.title,
                synopsis: item.synopsis ?? "",
                coverImageRemoteURL: item.coverImageURL ?? "",
                airingStatusRaw: item.status ?? "Finished Airing",
                englishTitle: item.englishTitle,
                japaneseTitle: item.japaneseTitle,
                totalEpisodes: item.episodes,
                seasonYear: yearStr
            )
            anime.setWatchStatus(status)
            modelContext.insert(anime)
            try? modelContext.save()
        }
    }

    private func updateStatus(for tracked: TrackedAnime, to status: WatchStatus) {
        withAnimation(.spring(response: 0.3)) {
            tracked.setWatchStatus(status)
            try? modelContext.save()
        }
    }

    private func removeFromLibrary(tracked: TrackedAnime) {
        withAnimation(.spring(response: 0.3)) {
            modelContext.delete(tracked)
            try? modelContext.save()
        }
    }
}
