import SwiftUI
import SwiftData
import Observation

public enum SidebarSection: String, Hashable, CaseIterable {
    case library = "MY LIBRARY"
    case explore = "EXPLORE"
    case data = "DATA"
}

public enum SidebarSelection: Hashable, Identifiable {
    case allAnime
    case watchStatus(WatchStatus)
    case search
    case weeklyCalendar
    case sequelAlerts
    case backup

    public var id: String {
        switch self {
        case .allAnime: return "allAnime"
        case .watchStatus(let status): return "status_\(status.rawValue)"
        case .search: return "search"
        case .weeklyCalendar: return "weeklyCalendar"
        case .sequelAlerts: return "sequelAlerts"
        case .backup: return "backup"
        }
    }

    public var title: String {
        switch self {
        case .allAnime: return "All Anime"
        case .watchStatus(let status): return status.displayName
        case .search: return "Search"
        case .weeklyCalendar: return "Weekly Calendar"
        case .sequelAlerts: return "Sequel Alerts"
        case .backup: return "Import / Export JSON & MAL"
        }
    }

    public var systemImage: String {
        switch self {
        case .allAnime: return "square.grid.2x2.fill"
        case .watchStatus(let status): return status.systemImage
        case .search: return "magnifyingglass"
        case .weeklyCalendar: return "calendar.badge.clock"
        case .sequelAlerts: return "bell.badge.fill"
        case .backup: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

public enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Poster Grid"
    case table = "Compact Table"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .table: return "list.bullet"
        }
    }
}

public enum LibrarySortOption: String, CaseIterable, Identifiable {
    case dateAddedDesc = "Date Added (Newest First)"
    case dateAddedAsc = "Date Added (Oldest First)"
    case titleAsc = "Title (A-Z)"
    case scoreDesc = "Score (Highest First)"
    case progressDesc = "Episode Progress"
    case lastUpdatedDesc = "Recently Updated"

    public var id: String { rawValue }
}

@Observable
public final class NavigationState {
    public var selectedSidebar: SidebarSelection? = .allAnime
    public var selectedAnimeID: PersistentIdentifier? = nil
    public var selectedJikanDTO: JikanAnimeDTO? = nil
    public var showInspector: Bool = true
    public var viewMode: ViewMode = .grid
    public var librarySearchQuery: String = ""
    public var selectedAiringStatusFilter: AiringStatus? = nil
    public var selectedSortOption: LibrarySortOption = .dateAddedDesc

    public init() {}

    public func selectTracked(_ animeID: PersistentIdentifier) {
        self.selectedAnimeID = animeID
        self.selectedJikanDTO = nil
        self.showInspector = true
    }

    public func selectDTO(_ dto: JikanAnimeDTO) {
        self.selectedJikanDTO = dto
        self.selectedAnimeID = nil
        self.showInspector = true
    }
}
