import Foundation
import SwiftUI

public struct RelatedAnimeItem: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: Int { malID }
    public let malID: Int
    public let relationType: String
    public let title: String
    public let englishTitle: String?
    public let japaneseTitle: String?
    public let coverImageURL: String?
    public let format: String?
    public let status: String?
    public let episodes: Int?
    public let season: String?
    public let seasonYear: Int?
    public let synopsis: String?

    public init(
        malID: Int,
        relationType: String,
        title: String,
        englishTitle: String? = nil,
        japaneseTitle: String? = nil,
        coverImageURL: String? = nil,
        format: String? = nil,
        status: String? = nil,
        episodes: Int? = nil,
        season: String? = nil,
        seasonYear: Int? = nil,
        synopsis: String? = nil
    ) {
        self.malID = malID
        self.relationType = relationType
        self.title = title
        self.englishTitle = englishTitle
        self.japaneseTitle = japaneseTitle
        self.coverImageURL = coverImageURL
        self.format = format
        self.status = status
        self.episodes = episodes
        self.season = season
        self.seasonYear = seasonYear
        self.synopsis = synopsis
    }

    public var priorityRank: Int {
        switch relationType.uppercased() {
        case "PREQUEL": return 0
        case "SEQUEL": return 1
        case "PARENT": return 2
        case "SIDE_STORY": return 3
        case "SPIN_OFF": return 4
        case "ALTERNATIVE": return 5
        default: return 6
        }
    }

    public var relationDisplayName: String {
        switch relationType.uppercased() {
        case "PREQUEL": return "Prequel"
        case "SEQUEL": return "Sequel"
        case "PARENT": return "Parent Story"
        case "SIDE_STORY": return "Side Story"
        case "SPIN_OFF": return "Spin-Off"
        case "ALTERNATIVE": return "Alternative"
        case "CHARACTER": return "Character"
        case "SUMMARY": return "Summary"
        default: return relationType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var relationIcon: String {
        switch relationType.uppercased() {
        case "PREQUEL": return "arrow.left.circle.fill"
        case "SEQUEL": return "arrow.right.circle.fill"
        case "PARENT": return "book.fill"
        case "SIDE_STORY": return "rectangle.stack.fill"
        case "SPIN_OFF": return "arrow.triangle.branch"
        default: return "link"
        }
    }

    public var badgeColor: Color {
        switch relationType.uppercased() {
        case "PREQUEL": return Color.blue
        case "SEQUEL": return Color.purple
        case "PARENT": return Color.indigo
        case "SIDE_STORY": return Color.teal
        case "SPIN_OFF": return Color.orange
        default: return Color.secondary
        }
    }

    public func displayTitle(for preference: TitleLanguagePreference = .english) -> String {
        switch preference {
        case .english:
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"
        case .romaji:
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            return "Untitled Anime"
        case .native:
            if let jp = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
                return jp
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
                return en
            }
            return "Untitled Anime"
        }
    }

    public var metadataSubtitle: String {
        var parts: [String] = []

        if let fmt = format, !fmt.isEmpty {
            let cleanFormat = fmt.replacingOccurrences(of: "_", with: " ").capitalized
            parts.append(cleanFormat)
        }

        if let ep = episodes, ep > 0 {
            parts.append("\(ep) ep\(ep > 1 ? "s" : "")")
        }

        if let year = seasonYear {
            if let s = season?.capitalized {
                parts.append("\(s) \(year)")
            } else {
                parts.append("\(year)")
            }
        }

        if parts.isEmpty {
            if let st = status {
                parts.append(st.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }

        return parts.joined(separator: " • ")
    }

    public var asJikanDTO: JikanAnimeDTO {
        var images: JikanImagesDTO? = nil
        if let cover = coverImageURL, !cover.isEmpty {
            let jpg = JikanImageFormatDTO(imageUrl: cover, smallImageUrl: nil, largeImageUrl: cover)
            images = JikanImagesDTO(jpg: jpg, webp: nil)
        }

        var mappedStatus: String? = nil
        if let st = status {
            switch st.uppercased() {
            case "FINISHED": mappedStatus = "Finished Airing"
            case "RELEASING": mappedStatus = "Currently Airing"
            case "NOT_YET_RELEASED": mappedStatus = "Not yet aired"
            case "CANCELLED": mappedStatus = "Cancelled"
            default: mappedStatus = st.capitalized
            }
        }

        return JikanAnimeDTO(
            malId: malID,
            title: title,
            titleEnglish: englishTitle,
            titleJapanese: japaneseTitle,
            synopsis: synopsis,
            images: images,
            status: mappedStatus,
            episodes: episodes,
            season: season?.lowercased(),
            year: seasonYear
        )
    }
}
