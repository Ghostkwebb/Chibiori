import SwiftUI
import SwiftData

@MainActor
public struct LibraryContainerView: View {
    let watchStatusFilter: WatchStatus?
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext

    @Query private var allAnime: [TrackedAnime]
    @State private var hydrationService = MetadataHydrationService.shared
    @State private var showGridSizePopover = false

    public init(watchStatusFilter: WatchStatus? = nil) {
        self.watchStatusFilter = watchStatusFilter
        // Default sort by dateAdded descending per specification
        self._allAnime = Query(sort: \TrackedAnime.dateAdded, order: .reverse)
    }

    private var filteredAnime: [TrackedAnime] {
        var list = allAnime

        // 1. Watch Status Filter (Sidebar selection)
        if let status = watchStatusFilter {
            list = list.filter { $0.watchStatus == status }
        }

        // 2. Airing Status Filter (Toolbar pill)
        if let airing = navState.selectedAiringStatusFilter {
            list = list.filter { $0.airingStatus == airing }
        }

        // 3. Local Search Query
        let query = navState.librarySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter { anime in
                anime.title.localizedCaseInsensitiveContains(query) ||
                (anime.englishTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                (anime.japaneseTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                (anime.customTitleOverride?.localizedCaseInsensitiveContains(query) ?? false) ||
                anime.genres.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            }
        }

        // 4. Custom Sort Option
        switch navState.selectedSortOption {
        case .dateAddedDesc:
            list.sort { $0.dateAdded > $1.dateAdded }
        case .dateAddedAsc:
            list.sort { $0.dateAdded < $1.dateAdded }
        case .titleAsc:
            list.sort {
                $0.displayTitle(for: navState.titleLanguagePreference)
                    .localizedCaseInsensitiveCompare($1.displayTitle(for: navState.titleLanguagePreference)) == .orderedAscending
            }
        case .scoreDesc:
            list.sort { ($0.malScore ?? 0) > ($1.malScore ?? 0) }
        case .progressDesc:
            list.sort { $0.currentEpisodeProgress > $1.currentEpisodeProgress }
        case .lastUpdatedDesc:
            list.sort { $0.statusLastUpdatedAt > $1.statusLastUpdatedAt }
        }

        return list
    }

    public var body: some View {
        @Bindable var state = navState

        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Background Hydration Banner if active
                if hydrationService.isHydrating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text(hydrationService.statusMessage ?? "Fetching anime posters & details...")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if filteredAnime.isEmpty {
                    emptyStateView
                } else {
                    switch state.viewMode {
                    case .grid:
                        AnimeGridView(
                            animes: filteredAnime,
                            selectedAnimeID: $state.selectedAnimeID
                        )
                    case .table:
                        AnimeTableView(
                            animes: filteredAnime,
                            selectedAnimeID: $state.selectedAnimeID
                        )
                    }
                }
            }
        }
        .navigationTitle(watchStatusFilter?.displayName ?? "All Anime")
        .navigationSubtitle("\(filteredAnime.count) \(filteredAnime.count == 1 ? "anime" : "animes")")
        .searchable(
            text: $state.librarySearchQuery,
            placement: .toolbar,
            prompt: "Search local library..."
        )
        .onAppear {
            let missing = allAnime.filter { $0.coverImageRemoteURL.isEmpty }
            if !missing.isEmpty && !hydrationService.isHydrating {
                Task {
                    await hydrationService.hydrateMissingMetadata(context: modelContext)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Airing Status Filter Pill / Menu
                Menu {
                    Button {
                        state.selectedAiringStatusFilter = nil
                    } label: {
                        HStack {
                            Text("All Airing Statuses")
                            if state.selectedAiringStatusFilter == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(AiringStatus.allCases) { status in
                        Button {
                            state.selectedAiringStatusFilter = status
                        } label: {
                            HStack {
                                Text(status.displayName)
                                if state.selectedAiringStatusFilter == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        state.selectedAiringStatusFilter?.displayName ?? "Airing Status",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .help("Filter by Airing Status")

                // Sort Options Menu
                Menu {
                    ForEach(LibrarySortOption.allCases) { option in
                        Button {
                            state.selectedSortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if state.selectedSortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort order")

                // Title Language Preference Menu
                Menu {
                    ForEach(TitleLanguagePreference.allCases) { pref in
                        Button {
                            state.titleLanguagePreference = pref
                        } label: {
                            HStack {
                                Image(systemName: pref.icon)
                                Text(pref.displayName)
                                if state.titleLanguagePreference == pref {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(state.titleLanguagePreference.displayName, systemImage: state.titleLanguagePreference.icon)
                }
                .help("Preferred Title Language (English, Romaji, Native)")

                // Grid Size Slider Popover (Visible in Grid Mode)
                if state.viewMode == .grid {
                    Button {
                        showGridSizePopover.toggle()
                    } label: {
                        Label("Grid Size", systemImage: "circle.grid.2x2")
                    }
                    .help("Adjust Grid Poster Size (Slider & Presets)")
                    .popover(isPresented: $showGridSizePopover, arrowEdge: .bottom) {
                        GridSizeControlPopover(gridCardSize: $state.gridCardSize)
                    }
                }

                // View Mode Picker (Poster Grid vs Compact Table)
                Picker("View Mode", selection: $state.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Toggle between Poster Grid and Compact Table")

                // Inspector Toggle
                Button {
                    withAnimation {
                        state.showInspector.toggle()
                    }
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector Panel")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: watchStatusFilter?.systemImage ?? "film.stack")
                .font(.system(size: 46))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.cyan, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(emptyStateTitle)
                .font(.system(size: 16, weight: .bold))

            Text(emptyStateDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                navState.selectedSidebar = .search
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Anime")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(32)
        .glassCard(cornerRadius: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if !navState.librarySearchQuery.isEmpty {
            return "No matching anime found"
        }
        if let status = watchStatusFilter {
            return "No anime in \(status.displayName)"
        }
        return "Your library is empty"
    }

    private var emptyStateDescription: String {
        if !navState.librarySearchQuery.isEmpty {
            return "Try searching for a different keyword or clear the search filter."
        }
        if let status = watchStatusFilter {
            return "Anime marked as \"\(status.displayName)\" will appear here."
        }
        return "Search MyAnimeList via the Discover tab to add anime to your local collection."
    }
}
