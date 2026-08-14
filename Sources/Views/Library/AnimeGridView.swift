import SwiftUI
import SwiftData
import AppKit

@MainActor
public struct AnimeGridView: View {
    let animes: [TrackedAnime]
    @Binding var selectedAnimeID: PersistentIdentifier?

    @FocusState private var isFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    public init(animes: [TrackedAnime], selectedAnimeID: Binding<PersistentIdentifier?>) {
        self.animes = animes
        self._selectedAnimeID = selectedAnimeID
    }

    private var estimatedColumnsCount: Int {
        let windowWidth = NSApp.keyWindow?.frame.width ?? 1200
        let availableWidth = max(300, windowWidth - 340) // subtract sidebar and inspector
        return max(1, Int(availableWidth / 190))
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
                selectDelta(estimatedColumnsCount, proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                selectDelta(-estimatedColumnsCount, proxy: proxy)
                return .handled
            }
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
