import Foundation
import SwiftUI

public enum AiringStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentlyAiring = "Currently Airing"
    case finishedAiring = "Finished Airing"
    case notYetAired = "Not Yet Aired"

    public var id: String { rawValue }

    public var displayName: String {
        rawValue
    }

    public var shortDisplayName: String {
        switch self {
        case .currentlyAiring: return "Airing"
        case .finishedAiring: return "Finished"
        case .notYetAired: return "Upcoming"
        }
    }

    public var systemImage: String {
        switch self {
        case .currentlyAiring: return "antenna.radiowaves.left.and.right"
        case .finishedAiring: return "checkmark.circle.fill"
        case .notYetAired: return "clock.badge.questionmark"
        }
    }

    public var dotColor: Color {
        switch self {
        case .currentlyAiring: return Color(red: 0.2, green: 0.85, blue: 0.45) // Vibrant Green
        case .finishedAiring: return Color(red: 0.65, green: 0.45, blue: 0.95) // Sleek Purple
        case .notYetAired: return Color(red: 0.25, green: 0.75, blue: 1.0)   // Bright Cyan
        }
    }

    public var badgeColor: Color {
        dotColor
    }

    public static func from(raw: String?) -> AiringStatus? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        // MAL XML status codes: 1 = Airing, 2 = Finished, 3 = Not Yet Aired
        if lower == "1" || lower == "currently airing" || lower.contains("releasing") || (lower.contains("airing") && !lower.contains("finished") && !lower.contains("not")) {
            return .currentlyAiring
        } else if lower == "2" || lower == "finished airing" || lower.contains("finished") || lower.contains("complete") || lower == "aired" {
            return .finishedAiring
        } else if lower == "3" || lower == "not yet aired" || lower.contains("not yet") || lower.contains("not_yet") || lower.contains("upcoming") || lower.contains("to be aired") || lower.contains("tba") || lower.contains("unreleased") {
            return .notYetAired
        }
        return AiringStatus(rawValue: raw)
    }
}
