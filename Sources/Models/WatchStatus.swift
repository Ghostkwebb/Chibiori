import Foundation
import SwiftUI

public enum WatchStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case planToWatch = "planToWatch"
    case watching = "watching"
    case completed = "completed"
    case onHold = "onHold"
    case dropped = "dropped"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .planToWatch: return "Plan to Watch"
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .onHold: return "On Hold"
        case .dropped: return "Dropped"
        }
    }

    public var systemImage: String {
        switch self {
        case .planToWatch: return "bookmark.fill"
        case .watching: return "play.circle.fill"
        case .completed: return "checkmark.seal.fill"
        case .onHold: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .planToWatch: return .blue
        case .watching: return .green
        case .completed: return .purple
        case .onHold: return .orange
        case .dropped: return .red
        }
    }
}
