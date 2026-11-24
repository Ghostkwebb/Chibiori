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

    public var menuSymbolName: String {
        switch self {
        case .planToWatch: return "bookmark.fill"
        case .watching: return "play.fill"
        case .completed: return "checkmark"
        case .onHold: return "pause.fill"
        case .dropped: return "xmark"
        }
    }

    @MainActor
    private static var iconImageCache: [String: NSImage] = [:]

    @MainActor
    public func coloredIconAttachment(size: CGFloat = 14) -> NSTextAttachment {
        let iconSize = NSSize(width: size, height: size)
        let cacheKey = "\(self.rawValue)_\(Int(size.rounded()))"

        let image: NSImage
        if let cached = Self.iconImageCache[cacheKey] {
            image = cached
        } else {
            let rendered = NSImage(size: iconSize, flipped: false) { _ in
                let config = NSImage.SymbolConfiguration(pointSize: size - 2, weight: .bold)
                    .applying(.init(paletteColors: [self.nsColor]))
                if let sym = NSImage(systemSymbolName: self.menuSymbolName, accessibilityDescription: self.displayName)?.withSymbolConfiguration(config) {
                    let ox = (iconSize.width - sym.size.width) / 2
                    let oy = (iconSize.height - sym.size.height) / 2
                    sym.draw(in: NSRect(x: ox, y: oy, width: sym.size.width, height: sym.size.height))
                }
                return true
            }
            rendered.isTemplate = false
            Self.iconImageCache[cacheKey] = rendered
            image = rendered
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2.5, width: iconSize.width, height: iconSize.height)
        return attachment
    }
}
