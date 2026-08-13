import SwiftUI
import Observation

public enum DiscoverCategory: String, CaseIterable, Identifiable {
    case seasonNow = "Current Season"
    case topAiring = "Top Airing"
    case topPopular = "Most Popular"
    case topAllTime = "Top All Time"

    public var id: String { rawValue }
}

@Observable
@MainActor
public final class DiscoverViewModel {
    public var searchQuery: String = ""
    public var selectedCategory: DiscoverCategory = .seasonNow
    public var results: [JikanAnimeDTO] = []
    public var isLoading: Bool = false
    public var isLoadingMore: Bool = false
    public var hasMorePages: Bool = true
    public var currentPage: Int = 1
    public var errorMessage: String? = nil

    private var searchTask: Task<Void, Never>? = nil

    public init() {}

    public func loadCategoryData() {
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data: [JikanAnimeDTO]
                switch selectedCategory {
                case .seasonNow:
                    data = try await JikanAPIService.shared.fetchCurrentSeason(page: 1)
                case .topAiring:
                    data = try await JikanAPIService.shared.fetchTopAnime(page: 1, filter: "airing")
                case .topPopular:
                    data = try await JikanAPIService.shared.fetchTopAnime(page: 1, filter: "bypopularity")
                case .topAllTime:
                    data = try await JikanAPIService.shared.fetchTopAnime(page: 1)
                }
                self.results = data.deduplicatedByID()
                self.hasMorePages = data.count >= 20
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    public func performSearch() {
        searchTask?.cancel()

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadCategoryData()
            return
        }

        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil

        searchTask = Task {
            // Debounce delay
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let data = try await JikanAPIService.shared.fetchSearchResults(query: trimmed, page: 1)
                guard !Task.isCancelled else { return }
                self.results = data.deduplicatedByID()
                self.hasMorePages = data.count >= 20
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    public func loadMore() {
        guard !isLoading && !isLoadingMore && hasMorePages else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let newItems: [JikanAnimeDTO]
                if !trimmed.isEmpty {
                    newItems = try await JikanAPIService.shared.fetchSearchResults(query: trimmed, page: nextPage)
                } else {
                    switch selectedCategory {
                    case .seasonNow:
                        newItems = try await JikanAPIService.shared.fetchCurrentSeason(page: nextPage)
                    case .topAiring:
                        newItems = try await JikanAPIService.shared.fetchTopAnime(page: nextPage, filter: "airing")
                    case .topPopular:
                        newItems = try await JikanAPIService.shared.fetchTopAnime(page: nextPage, filter: "bypopularity")
                    case .topAllTime:
                        newItems = try await JikanAPIService.shared.fetchTopAnime(page: nextPage)
                    }
                }

                if newItems.isEmpty {
                    self.hasMorePages = false
                } else {
                    self.currentPage = nextPage
                    self.results = (self.results + newItems).deduplicatedByID()
                    self.hasMorePages = newItems.count >= 20
                }
                self.isLoadingMore = false
            } catch {
                self.isLoadingMore = false
            }
        }
    }
}
