import SwiftUI
import SwiftData

public struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trackedAnimes: [TrackedAnime]

    @Environment(NavigationState.self) private var navState
    @State private var viewModel = DiscoverViewModel()
    @FocusState private var isGridFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    public init() {}

    private var estimatedColumnsCount: Int {
        let windowWidth = NSApp.keyWindow?.frame.width ?? 1200
        let availableWidth = max(300, windowWidth - 340)
        return max(1, Int(availableWidth / 190))
    }

    @State private var trackedMap: [Int: TrackedAnime] = [:]

    public var body: some View {
        @Bindable var state = navState

        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Category selector if search is empty
                if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(DiscoverCategory.allCases) { category in
                                let isSelected = viewModel.selectedCategory == category
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        viewModel.selectedCategory = category
                                        viewModel.loadCategoryData()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isSelected {
                                            Image(systemName: "sparkle")
                                                .font(.system(size: 11))
                                        }
                                        Text(category.rawValue)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .glassPill(tint: isSelected ? .accentColor : .secondary, isSelected: isSelected)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                ZStack {
                    if viewModel.isLoading {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Fetching MyAnimeList metadata...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .glassCard(cornerRadius: 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.orange)
                            Text("Unable to load anime")
                                .font(.system(size: 16, weight: .bold))
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                            Button("Retry") {
                                if viewModel.searchQuery.isEmpty {
                                    viewModel.loadCategoryData()
                                } else {
                                    viewModel.performSearch()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(28)
                        .glassCard(cornerRadius: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.results.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 44))
                                .foregroundStyle(.tertiary)
                            Text("No results found")
                                .font(.system(size: 16, weight: .bold))
                            Text("Try searching with different terms.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(28)
                        .glassCard(cornerRadius: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(viewModel.results) { dto in
                                        let isDTOSelected = state.selectedJikanDTO?.malId == dto.malId
                                        let matchingTracked = trackedMap[dto.malId]
                                        let isTrackedSelected = matchingTracked != nil && matchingTracked?.persistentModelID == state.selectedAnimeID
                                        let isCardSelected = isDTOSelected || isTrackedSelected

                                        DiscoverAnimeCard(
                                            dto: dto,
                                            existingTracked: matchingTracked,
                                            isSelected: isCardSelected,
                                            onSelect: {
                                                isGridFocused = true
                                                if let tracked = matchingTracked {
                                                    state.selectTracked(tracked.persistentModelID)
                                                } else {
                                                    state.selectDTO(dto)
                                                }
                                            }
                                        ) { status in
                                            withAnimation(.spring(response: 0.3)) {
                                                let anime = addAnimeToLibrary(dto: dto, status: status)
                                                state.selectTracked(anime.persistentModelID)
                                            }
                                        }
                                        .equatable()
                                        .id(dto.malId)
                                    }
                                }
                                .padding(16)

                                // Show More Button / Footer
                                if !viewModel.results.isEmpty {
                                    VStack(spacing: 8) {
                                        if viewModel.hasMorePages {
                                            Button {
                                                viewModel.loadMore()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if viewModel.isLoadingMore {
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                        Text("Loading More Anime...")
                                                            .font(.system(size: 12, weight: .bold))
                                                    } else {
                                                        Image(systemName: "arrow.down.circle.fill")
                                                            .font(.system(size: 14))
                                                        Text("Show More Anime")
                                                            .font(.system(size: 13, weight: .bold))
                                                    }
                                                }
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 10)
                                                .glassPill(tint: .accentColor, isSelected: false)
                                                .foregroundStyle(Color.white)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(viewModel.isLoadingMore)
                                        } else {
                                            Text("You've reached the end of the results")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.tertiary)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.bottom, 24)
                                }
                            }
                            .smooth120HzScroll()
                            .focusable()
                            .focused($isGridFocused)
                            .focusEffectDisabled()
                            .onAppear {
                                isGridFocused = true
                            }
                            .onTapGesture {
                                isGridFocused = true
                            }
                            .onKeyPress(.rightArrow) {
                                selectDelta(1, proxy: proxy, state: state)
                                return .handled
                            }
                            .onKeyPress(.leftArrow) {
                                selectDelta(-1, proxy: proxy, state: state)
                                return .handled
                            }
                            .onKeyPress(.downArrow) {
                                selectDelta(estimatedColumnsCount, proxy: proxy, state: state)
                                return .handled
                            }
                            .onKeyPress(.upArrow) {
                                selectDelta(-estimatedColumnsCount, proxy: proxy, state: state)
                                return .handled
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(
            text: $viewModel.searchQuery,
            prompt: "Search anime (e.g. Steins;Gate, Jujutsu Kaisen)..."
        )
        .onChange(of: viewModel.searchQuery) { _, _ in
            viewModel.performSearch()
        }
        .onChange(of: trackedAnimes, initial: true) { _, newItems in
            var map: [Int: TrackedAnime] = [:]
            for item in newItems {
                map[item.malID] = item
            }
            self.trackedMap = map
        }
        .onAppear {
            if viewModel.results.isEmpty {
                viewModel.loadCategoryData()
            }
        }
    }

    @discardableResult
    private func addAnimeToLibrary(dto: JikanAnimeDTO, status: WatchStatus) -> TrackedAnime {
        let anime = TrackedAnime(
            malID: dto.malId,
            title: dto.title,
            synopsis: dto.synopsis ?? "",
            coverImageRemoteURL: dto.coverImageURL,
            airingStatusRaw: dto.status ?? "Finished Airing",
            japaneseTitle: dto.titleJapanese,
            totalEpisodes: dto.episodes,
            broadcastDayRaw: dto.broadcast?.day,
            broadcastTimeUTC: dto.broadcast?.time,
            malScore: dto.score,
            seasonYear: dto.seasonYearFormatted,
            genres: dto.genreNames
        )
        anime.setWatchStatus(status)
        modelContext.insert(anime)
        try? modelContext.save()

        if !dto.coverImageURL.isEmpty {
            Task {
                let (_, filename) = await CoverImageManager.shared.loadImage(
                    malID: dto.malId,
                    remoteURLString: dto.coverImageURL
                )
                if let filename {
                    anime.coverImageFilename = filename
                    try? modelContext.save()
                }
            }
        }
        return anime
    }

    @MainActor
    private func selectDelta(_ delta: Int, proxy: ScrollViewProxy, state: NavigationState) {
        guard !viewModel.results.isEmpty else { return }
        let currentMalID = state.selectedJikanDTO?.malId ??
            (trackedAnimes.first(where: { $0.persistentModelID == state.selectedAnimeID })?.malID ?? -1)

        let currentIndex = viewModel.results.firstIndex(where: { $0.malId == currentMalID }) ?? -1
        var nextIndex = currentIndex + delta
        if currentIndex == -1 {
            nextIndex = delta >= 0 ? 0 : viewModel.results.count - 1
        }
        nextIndex = max(0, min(viewModel.results.count - 1, nextIndex))
        let targetDTO = viewModel.results[nextIndex]

        if let tracked = trackedMap[targetDTO.malId] {
            state.selectTracked(tracked.persistentModelID)
        } else {
            state.selectDTO(targetDTO)
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(targetDTO.malId, anchor: .center)
        }
    }
}
