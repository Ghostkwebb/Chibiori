import Foundation
import SwiftUI

public enum TitleLanguagePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "English"
    case romaji = "Romaji"
    case native = "Native"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .romaji: return "Romaji (Main)"
        case .native: return "Native (JP / CN)"
        }
    }

    public var shortName: String {
        switch self {
        case .english: return "EN"
        case .romaji: return "RO"
        case .native: return "JP/CN"
        }
    }

    public var icon: String {
        switch self {
        case .english: return "globe.americas.fill"
        case .romaji: return "character.book.closed.fill"
        case .native: return "character.bubble.fill"
        }
    }
}
