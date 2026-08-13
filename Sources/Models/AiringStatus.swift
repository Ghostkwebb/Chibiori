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

    public var systemImage: String {
        switch self {
        case .currentlyAiring: return "antenna.radiowaves.left.and.right"
        case .finishedAiring: return "checkmark.circle.fill"
        case .notYetAired: return "clock.badge.questionmark"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .currentlyAiring: return .teal
        case .finishedAiring: return .secondary
        case .notYetAired: return .indigo
        }
    }

    public static func from(raw: String?) -> AiringStatus? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.contains("currently") || lower.contains("airing") && !lower.contains("finished") && !lower.contains("not") {
            return .currentlyAiring
        } else if lower.contains("finished") || lower.contains("complete") {
            return .finishedAiring
        } else if lower.contains("not yet") || lower.contains("upcoming") || lower.contains("to be aired") {
            return .notYetAired
        }
        return AiringStatus(rawValue: raw)
    }
}
