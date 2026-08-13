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

    public static var currentDay: Weekday {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}

@Observable
@MainActor
public final class ScheduleViewModel {
    public var selectedDay: Weekday = .currentDay
    public var schedules: [JikanAnimeDTO] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    public init() {}

    public func loadSchedule() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await JikanAPIService.shared.fetchSchedules(day: selectedDay.rawValue)
                self.schedules = data
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
