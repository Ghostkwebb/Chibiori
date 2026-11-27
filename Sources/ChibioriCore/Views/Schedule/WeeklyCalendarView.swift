import SwiftUI
import SwiftData
import AppKit

@MainActor
public struct WeeklyCalendarView: View {
    @Environment(NavigationState.self) private var navState
    @Environment(LibraryStore.self) private var libraryStore
    @State private var viewModel = ScheduleViewModel()
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

    public var body: some View {
        @Bindable var state = navState

        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Day selector tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Weekday.allCases) { day in
                            let isSelected = viewModel.selectedDay == day
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.selectedDay = day
                                    viewModel.loadSchedule()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(day.displayName)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    if day == Weekday.currentDay {
                                        Circle()
                                            .fill(isSelected ? Color.white : Color.accentColor)
                                            .frame(width: 5, height: 5)
                                    }
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

                // Schedule Content Grid
                Group {
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading broadcast schedule...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.orange)
                            Text("Unable to load schedule")
                                .font(.system(size: 16, weight: .bold))
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                viewModel.loadSchedule()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(28)
                        .glassCard(cornerRadius: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.schedules.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 44))
                                .foregroundStyle(.tertiary)
                            Text("No shows scheduled for \(viewModel.selectedDay.displayName)")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .padding(28)
                        .glassCard(cornerRadius: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(viewModel.schedules) { dto in
                                        let tracked = libraryStore.anime(forMalID: dto.malId)
                                        let isCardSelected: Bool = (state.selectedJikanDTO?.malId == dto.malId) ||
                                            (tracked != nil && tracked?.persistentModelID == state.selectedAnimeID)
                                        let scoreDisplay = tracked.flatMap {
                                            libraryStore.primaryScoreDisplay(for: $0, preference: navState.preferredScoreSource)
                                        } ?? libraryStore.siteScoresByMalID[dto.malId]?.badge(for: navState.preferredScoreSource)
                                        let snapshot = DiscoverCardSnapshot(
                                            dto: dto,
                                            trackedStatus: tracked?.watchStatus,
                                            titleLanguagePreference: navState.titleLanguagePreference,
                                            isSelected: isCardSelected,
                                            scoreDisplay: scoreDisplay
                                        )

                                        DiscoverAnimeCard(
                                            snapshot: snapshot,
                                            onSelect: {
                                                isGridFocused = true
                                                if let tracked {
                                                    state.selectTracked(tracked.persistentModelID)
                                                } else {
                                                    state.selectDTO(dto)
                                                }
                                            },
                                            onStatusChange: { newStatus in
                                                if let tracked {
                                                    libraryStore.setWatchStatus(newStatus, for: tracked)
                                                }
                                            }
                                        ) { status in
                                            withAnimation(.spring(response: 0.3)) {
                                                let anime = libraryStore.addOrUpdate(from: dto, status: status)
                                                state.selectTracked(anime.persistentModelID)
                                            }
                                        }
                                        .equatable()
                                        .id(dto.malId)
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationTitle("Weekly Calendar")
        .navigationSubtitle("Airing on \(viewModel.selectedDay.displayName)")
        .onAppear {
            if viewModel.schedules.isEmpty {
                viewModel.loadSchedule()
            }
        }
    }

    @MainActor
    private func selectDelta(_ delta: Int, proxy: ScrollViewProxy, state: NavigationState) {
        guard !viewModel.schedules.isEmpty else { return }
        let currentIndex = viewModel.schedules.firstIndex(where: { dto in
            let tracked = libraryStore.anime(forMalID: dto.malId)
            return (state.selectedJikanDTO?.malId == dto.malId) ||
                (tracked != nil && tracked?.persistentModelID == state.selectedAnimeID)
        }) ?? -1
        var nextIndex = currentIndex + delta
        if currentIndex == -1 {
            nextIndex = delta >= 0 ? 0 : viewModel.schedules.count - 1
        }
        nextIndex = max(0, min(viewModel.schedules.count - 1, nextIndex))
        let target = viewModel.schedules[nextIndex]
        if let tracked = libraryStore.anime(forMalID: target.malId) {
            state.selectTracked(tracked.persistentModelID)
        } else {
            state.selectDTO(target)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(target.malId, anchor: .center)
        }
    }
}
