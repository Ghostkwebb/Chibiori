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

    private let apiService: JikanAPIService
    private var searchTask: Task<Void, Never>? = nil
    private var categoryTask: Task<Void, Never>? = nil
    private var loadMoreTask: Task<Void, Never>? = nil

    public init(apiService: JikanAPIService = .shared) {
        self.apiService = apiService
    }

    public func loadCategoryData() {
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        searchTask?.cancel()
        categoryTask?.cancel()
        loadMoreTask?.cancel()

        currentPage = 1
        hasMorePages = true
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        let category = selectedCategory
        categoryTask = Task {
            do {
                let data: [JikanAnimeDTO]
                switch category {
                case .seasonNow:
                    data = try await apiService.fetchCurrentSeason(page: 1)
                case .topAiring:
                    data = try await apiService.fetchTopAnime(page: 1, filter: "airing")
                case .topPopular:
                    data = try await apiService.fetchTopAnime(page: 1, filter: "bypopularity")
                case .topAllTime:
                    data = try await apiService.fetchTopAnime(page: 1)
                }
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

    public func performSearch() {
        searchTask?.cancel()
        categoryTask?.cancel()
        loadMoreTask?.cancel()

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadCategoryData()
            return
        }

        currentPage = 1
        hasMorePages = true
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            do {
                let data = try await apiService.fetchSearchResults(query: trimmed, page: 1)
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

        loadMoreTask?.cancel()
        isLoadingMore = true
        let nextPage = currentPage + 1
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = selectedCategory

        loadMoreTask = Task {
            do {
                let newItems: [JikanAnimeDTO]
                if !trimmed.isEmpty {
                    newItems = try await apiService.fetchSearchResults(query: trimmed, page: nextPage)
                } else {
                    switch category {
                    case .seasonNow:
                        newItems = try await apiService.fetchCurrentSeason(page: nextPage)
                    case .topAiring:
                        newItems = try await apiService.fetchTopAnime(page: nextPage, filter: "airing")
                    case .topPopular:
                        newItems = try await apiService.fetchTopAnime(page: nextPage, filter: "bypopularity")
                    case .topAllTime:
                        newItems = try await apiService.fetchTopAnime(page: nextPage)
                    }
                }
                guard !Task.isCancelled else { return }

                if newItems.isEmpty {
                    self.hasMorePages = false
                } else {
                    self.currentPage = nextPage
                    self.results = (self.results + newItems).deduplicatedByID()
                    self.hasMorePages = newItems.count >= 20
                }
                self.isLoadingMore = false
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoadingMore = false
            }
        }
    }
}
