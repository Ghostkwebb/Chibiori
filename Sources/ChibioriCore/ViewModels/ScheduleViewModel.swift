import SwiftUI
import Observation

public enum Weekday: String, CaseIterable, Identifiable {
    case monday = "monday"
    case tuesday = "tuesday"
    case wednesday = "wednesday"
    case thursday = "thursday"
    case friday = "friday"
    case saturday = "saturday"
    case sunday = "sunday"

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    /// Calendar weekday integer (`1 = Sunday ... 7 = Saturday`).
    public var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    public static var currentDay: Weekday {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return Weekday.allCases.first(where: { $0.calendarWeekday == weekday }) ?? .monday
    }
}

@Observable
@MainActor
public final class ScheduleViewModel {
    public var selectedDay: Weekday = .currentDay
    public var schedules: [JikanAnimeDTO] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    private let apiService: JikanAPIService
    private var loadTask: Task<Void, Never>? = nil

    public init(apiService: JikanAPIService = .shared) {
        self.apiService = apiService
    }

    public func loadSchedule() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let day = selectedDay.rawValue
        loadTask = Task {
            do {
                let data = try await apiService.fetchSchedules(day: day)
                guard !Task.isCancelled else { return }
                self.schedules = data
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
