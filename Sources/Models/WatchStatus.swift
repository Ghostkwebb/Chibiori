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
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(.init(paletteColors: [self.nsColor]))
            if let symbol = NSImage(systemSymbolName: self.systemImage, accessibilityDescription: self.displayName)?.withSymbolConfiguration(config) {
                symbol.isTemplate = false
                let ox = (size.width - symbol.size.width) / 2
                let oy = (size.height - symbol.size.height) / 2
                symbol.draw(in: NSRect(x: ox, y: oy, width: symbol.size.width, height: symbol.size.height))
                return true
            } else {
                self.nsColor.setFill()
                let circle = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10))
                circle.fill()
                return true
            }
        }
        img.isTemplate = false
        return img
    }

    public var coloredIndicatorDot: NSImage {
        let size = NSSize(width: 14, height: 14)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 28,
            pixelsHigh: 28,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        self.nsColor.setFill()
        let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 10, height: 10))
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }
}
