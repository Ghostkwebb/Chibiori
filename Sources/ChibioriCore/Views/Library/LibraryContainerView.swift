import SwiftUI
import SwiftData

@MainActor
public struct LibraryContainerView: View {
    let watchStatusFilter: WatchStatus?
    @Environment(NavigationState.self) private var navState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.modelContext) private var modelContext

    @State private var hydrationService = MetadataHydrationService.shared

    public init(watchStatusFilter: WatchStatus? = nil) {
        self.watchStatusFilter = watchStatusFilter
    }

    private var filteredAnime: [TrackedAnime] {
        libraryStore.filteredAnime(
            status: watchStatusFilter,
            airing: navState.selectedAiringStatusFilter,
            query: navState.librarySearchQuery,
            sortOption: navState.selectedSortOption,
            titlePreference: navState.titleLanguagePreference
        )
    }

    public var body: some View {
        @Bindable var state = navState
        let currentFilteredAnime = filteredAnime

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

                if currentFilteredAnime.isEmpty {
                    emptyStateView
                } else {
                    switch state.viewMode {
                    case .grid:
                        AnimeGridView(
                            animes: currentFilteredAnime,
                            selectedAnimeID: $state.selectedAnimeID
                        )
                    case .table:
                        AnimeTableView(
                            animes: currentFilteredAnime,
                            selectedAnimeID: $state.selectedAnimeID
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(watchStatusFilter?.displayName ?? "All Anime")
        .task {
            let hydrated = await hydrationService.hydrateMissingMetadata(context: modelContext)
            let synced = await hydrationService.syncActiveAiringStatuses(context: modelContext)
            if hydrated || synced {
                libraryStore.reload(notifyCloudSync: true)
            }
        }
        .navigationSubtitle("\(currentFilteredAnime.count) \(currentFilteredAnime.count == 1 ? "title" : "titles")")
        .searchable(
            text: $state.librarySearchQuery,
            placement: .toolbar,
            prompt: "Search local library..."
        )
        .onChange(of: watchStatusFilter, initial: true) { _, _ in
            let items = currentFilteredAnime.prefix(40).map { ($0.malID, $0.coverImageRemoteURL, $0.coverImageFilename) }
            CoverImageManager.shared.prefetchCovers(items: items)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Airing Status Filter Pill / Menu
                Menu {
                    Picker("Airing Status", selection: $state.selectedAiringStatusFilter) {
                        Text("All Airing Statuses").tag(AiringStatus?.none)
                        Divider()
                        ForEach(AiringStatus.allCases) { status in
                            Text(status.displayName).tag(AiringStatus?.some(status))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        state.selectedAiringStatusFilter?.displayName ?? "Airing Status",
                        systemImage: state.selectedAiringStatusFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                    )
                }
                .help("Filter by Airing Status")

                // Sort Options Menu
                Menu {
                    Picker("Sort Order", selection: $state.selectedSortOption) {
                        ForEach(LibrarySortOption.allCases) { option in
                            Text(option.displayName(for: watchStatusFilter)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort order")

                // Title Language Preference Menu
                Menu {
                    Picker("Title Language", selection: $state.titleLanguagePreference) {
                        ForEach(TitleLanguagePreference.allCases) { pref in
                            Label(pref.displayName, systemImage: pref.icon).tag(pref)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(state.titleLanguagePreference.displayName, systemImage: state.titleLanguagePreference.icon)
                }
                .help("Preferred Title Language (English, Romaji, Native)")

                // Grid Size Slider Popover (Visible in Grid Mode)
                if state.viewMode == .grid {
                    Button {
                        state.showGridSizePopover.toggle()
                    } label: {
                        Label("Grid Size", systemImage: "circle.grid.2x2")
                    }
                    .help("Adjust Grid Poster Size (Slider & Presets)")
                    .popover(isPresented: $state.showGridSizePopover, arrowEdge: .bottom) {
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

                // Refresh Active Library Airing Statuses & Metadata
                Button {
                    Task {
                        let synced = await hydrationService.syncActiveAiringStatuses(context: modelContext, forceAll: true)
                        if synced {
                            libraryStore.reload(notifyCloudSync: true)
                        }
                    }
                } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                .help("Refresh Airing Statuses & Episodes for All Active Anime")
                .disabled(hydrationService.isHydrating)

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
