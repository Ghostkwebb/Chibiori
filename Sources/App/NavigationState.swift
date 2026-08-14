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

    public static func from(id: String) -> SidebarSelection? {
        if id == "allAnime" { return .allAnime }
        if id == "search" { return .search }
        if id == "weeklyCalendar" { return .weeklyCalendar }
        if id == "sequelAlerts" { return .sequelAlerts }
        if id == "backup" { return .backup }
        if id.hasPrefix("status_") {
            let rawStatus = String(id.dropFirst("status_".count))
            if let status = WatchStatus(rawValue: rawStatus) {
                return .watchStatus(status)
            }
        }
        return nil
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
    public var selectedSidebar: SidebarSelection? = .allAnime {
        didSet {
            if let id = selectedSidebar?.id {
                UserDefaults.standard.set(id, forKey: "savedSidebarSelection")
            }
        }
    }
    public var selectedAnimeID: PersistentIdentifier? = nil
    public var selectedJikanDTO: JikanAnimeDTO? = nil
    public var showInspector: Bool = true {
        didSet {
            UserDefaults.standard.set(showInspector, forKey: "savedShowInspector")
        }
    }
    public var viewMode: ViewMode = .grid {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "savedViewMode")
        }
    }
    public var librarySearchQuery: String = ""
    public var selectedAiringStatusFilter: AiringStatus? = nil
    public var selectedSortOption: LibrarySortOption = .dateAddedDesc {
        didSet {
            UserDefaults.standard.set(selectedSortOption.rawValue, forKey: "savedSortOption")
        }
    }
    public var titleLanguagePreference: TitleLanguagePreference {
        didSet {
            UserDefaults.standard.set(titleLanguagePreference.rawValue, forKey: "preferredTitleLanguage")
        }
    }
    public var gridCardSize: Double {
        didSet {
            UserDefaults.standard.set(gridCardSize, forKey: "libraryGridCardSize")
        }
    }
    public var sidebarWidth: Double {
        didSet {
            UserDefaults.standard.set(sidebarWidth, forKey: "savedSidebarWidth")
        }
    }
    public var inspectorWidth: Double {
        didSet {
            UserDefaults.standard.set(inspectorWidth, forKey: "savedInspectorWidth")
        }
    }

    public init() {
        if let savedLang = UserDefaults.standard.string(forKey: "preferredTitleLanguage"),
           let pref = TitleLanguagePreference(rawValue: savedLang) {
            self.titleLanguagePreference = pref
        } else {
            self.titleLanguagePreference = .english
        }

        let savedGridSize = UserDefaults.standard.double(forKey: "libraryGridCardSize")
        if savedGridSize >= 110.0 && savedGridSize <= 260.0 {
            self.gridCardSize = savedGridSize
        } else {
            self.gridCardSize = 165.0
        }

        let savedSidebarW = UserDefaults.standard.double(forKey: "savedSidebarWidth")
        if savedSidebarW >= 190.0 && savedSidebarW <= 350.0 {
            self.sidebarWidth = savedSidebarW
        } else {
            self.sidebarWidth = 235.0
        }

        let savedInspectorW = UserDefaults.standard.double(forKey: "savedInspectorWidth")
        if savedInspectorW >= 280.0 && savedInspectorW <= 500.0 {
            self.inspectorWidth = savedInspectorW
        } else {
            self.inspectorWidth = 340.0
        }

        if UserDefaults.standard.object(forKey: "savedShowInspector") != nil {
            self.showInspector = UserDefaults.standard.bool(forKey: "savedShowInspector")
        } else {
            self.showInspector = true
        }

        if let savedMode = UserDefaults.standard.string(forKey: "savedViewMode"),
           let mode = ViewMode(rawValue: savedMode) {
            self.viewMode = mode
        } else {
            self.viewMode = .grid
        }

        if let savedSort = UserDefaults.standard.string(forKey: "savedSortOption"),
           let sort = LibrarySortOption(rawValue: savedSort) {
            self.selectedSortOption = sort
        } else {
            self.selectedSortOption = .dateAddedDesc
        }

        if let savedSidebar = UserDefaults.standard.string(forKey: "savedSidebarSelection"),
           let selection = SidebarSelection.from(id: savedSidebar) {
            self.selectedSidebar = selection
        } else {
            self.selectedSidebar = .allAnime
        }
    }

    public func zoomInGrid() {
        gridCardSize = min(260.0, gridCardSize + 20.0)
    }

    public func zoomOutGrid() {
        gridCardSize = max(110.0, gridCardSize - 20.0)
    }

    public func resetGridSize() {
        gridCardSize = 165.0
    }

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
