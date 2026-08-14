import Foundation
import SwiftUI
import AppKit

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

    public var nsColor: NSColor {
        switch self {
        case .planToWatch: return .systemBlue
        case .watching: return .systemGreen
        case .completed: return .systemPurple
        case .onHold: return .systemOrange
        case .dropped: return .systemRed
        }
    }

    public var coloredMenuIcon: NSImage {
        let config = NSImage.SymbolConfiguration(paletteColors: [self.nsColor])
        if let base = NSImage(systemSymbolName: self.systemImage, accessibilityDescription: displayName)?.withSymbolConfiguration(config) {
            base.isTemplate = false
            return base
        }
        return NSImage()
    }
}
