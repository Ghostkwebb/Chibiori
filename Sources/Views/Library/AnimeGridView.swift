import SwiftUI
import SwiftData
import AppKit

@MainActor
public struct AnimeGridView: View {
    @Environment(NavigationState.self) private var navState
    let animes: [TrackedAnime]
    @Binding var selectedAnimeID: PersistentIdentifier?
    @FocusState private var isFocused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: navState.gridCardSize, maximum: navState.gridCardSize * 1.35), spacing: 16)]
    }

    public init(animes: [TrackedAnime], selectedAnimeID: Binding<PersistentIdentifier?>) {
        self.animes = animes
        self._selectedAnimeID = selectedAnimeID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(animes) { anime in
                        AnimeCardView(
                            anime: anime,
                            titleLanguagePreference: navState.titleLanguagePreference,
                            isSelected: selectedAnimeID == anime.persistentModelID
                        ) {
                            isFocused = true
                            selectedAnimeID = anime.persistentModelID
                        }
                        .equatable()
                        .id(anime.persistentModelID)
                    }
                }
                .transaction { $0.animation = nil }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transaction { $0.animation = nil }
            .smooth120HzScroll()
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear {
                isFocused = true
            }
            .onTapGesture {
                isFocused = true
            }
            .onKeyPress(.rightArrow) {
                selectDelta(1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                selectDelta(-1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectDelta(currentColumnCount(), proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                selectDelta(-currentColumnCount(), proxy: proxy)
                return .handled
            }
        }
    }

    private func currentColumnCount() -> Int {
        guard let window = NSApp.keyWindow else { return 4 }
        let inspectorWidth: CGFloat = navState.showInspector ? navState.inspectorWidth : 0
        let sidebarWidth: CGFloat = 220
        let availableWidth = max(200, window.frame.width - sidebarWidth - inspectorWidth - 32)
        let cardSize = navState.gridCardSize
        return max(1, Int((availableWidth + 16) / (cardSize + 16)))
    }

    @MainActor
    private func selectDelta(_ delta: Int, proxy: ScrollViewProxy) {
        guard !animes.isEmpty else { return }
        let currentIndex = animes.firstIndex(where: { $0.persistentModelID == selectedAnimeID }) ?? -1
        var nextIndex = currentIndex + delta
        if currentIndex == -1 {
            nextIndex = delta >= 0 ? 0 : animes.count - 1
        }
        nextIndex = max(0, min(animes.count - 1, nextIndex))
        let target = animes[nextIndex]
        selectedAnimeID = target.persistentModelID
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(target.persistentModelID, anchor: .center)
        }
    }
}
