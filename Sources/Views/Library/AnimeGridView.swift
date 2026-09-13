import SwiftUI
import SwiftData
import AppKit

@MainActor
public struct AnimeGridView: View {
    @Environment(NavigationState.self) private var navState
    let animes: [TrackedAnime]
    @Binding var selectedAnimeID: PersistentIdentifier?

    @FocusState private var isFocused: Bool
    @State private var availableWidth: CGFloat = 800

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: navState.gridCardSize, maximum: navState.gridCardSize * 1.3), spacing: 16)]
    }

    public init(animes: [TrackedAnime], selectedAnimeID: Binding<PersistentIdentifier?>) {
        self.animes = animes
        self._selectedAnimeID = selectedAnimeID
    }

    private var exactColumnsCount: Int {
        let spacing: CGFloat = 16
        let padding: CGFloat = 32 // 16 left + 16 right
        let contentWidth = max(0, availableWidth - padding)
        let minCardWidth = navState.gridCardSize
        let count = Int((contentWidth + spacing) / (minCardWidth + spacing))
        return max(1, count)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(animes) { anime in
                        AnimeCardView(
                            anime: anime,
                            isSelected: selectedAnimeID == anime.persistentModelID
                        ) {
                            isFocused = true
                            selectedAnimeID = anime.persistentModelID
                        }
                        .equatable()
                        .id(anime.persistentModelID)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: GridWidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(GridWidthPreferenceKey.self) { newWidth in
                availableWidth = newWidth
            }
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
                selectDelta(exactColumnsCount, proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                selectDelta(-exactColumnsCount, proxy: proxy)
                return .handled
            }
        }
    }

    private struct GridWidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 800
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
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
