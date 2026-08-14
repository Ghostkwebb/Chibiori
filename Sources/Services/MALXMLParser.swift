import Foundation

public struct MALImportEntry: Sendable {
    public let malID: Int
    public let title: String
    public let status: WatchStatus
    public let watchedEpisodes: Int
    public let totalEpisodes: Int?
    public let userRating: Int?
    public let personalNotes: String
    public let airingStatusRaw: String?
    public let seriesStart: String?

    public init(
        malID: Int,
        title: String,
        status: WatchStatus,
        watchedEpisodes: Int,
        totalEpisodes: Int? = nil,
        userRating: Int? = nil,
        personalNotes: String = "",
        airingStatusRaw: String? = nil,
        seriesStart: String? = nil
    ) {
        self.malID = malID
        self.title = title
        self.status = status
        self.watchedEpisodes = watchedEpisodes
        self.totalEpisodes = totalEpisodes
        self.userRating = userRating
        self.personalNotes = personalNotes
        self.airingStatusRaw = airingStatusRaw
        self.seriesStart = seriesStart
    }
}

public final class MALXMLParser: NSObject, XMLParserDelegate {
    private var entries: [MALImportEntry] = []
    private var currentElement: String = ""
    private var currentText: String = ""

    // Current anime entry fields
    private var currentMalID: Int?
    private var currentTitle: String = ""
    private var currentStatusRaw: String = ""
    private var currentWatchedEpisodes: Int = 0
    private var currentTotalEpisodes: Int?
    private var currentScore: Int?
    private var currentComments: String = ""
    private var currentSeriesStatus: String? = nil
    private var currentSeriesStart: String? = nil

    public static func parse(data: Data, allowedStatuses: Set<WatchStatus>? = nil) -> [MALImportEntry] {
        let parser = MALXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        if let allowed = allowedStatuses {
            return parser.entries.filter { allowed.contains($0.status) }
        }
        return parser.entries
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "anime" {
            currentMalID = nil
            currentTitle = ""
            currentStatusRaw = ""
            currentWatchedEpisodes = 0
            currentTotalEpisodes = nil
            currentScore = nil
            currentComments = ""
            currentSeriesStatus = nil
            currentSeriesStart = nil
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            currentText += str
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "series_animedb_id":
            currentMalID = Int(trimmed)
        case "series_title":
            currentTitle = trimmed
        case "series_episodes":
            if let eps = Int(trimmed), eps > 0 {
                currentTotalEpisodes = eps
            }
        case "series_status":
            currentSeriesStatus = trimmed
        case "series_start":
            if !trimmed.isEmpty && trimmed != "0000-00-00" {
                currentSeriesStart = AnimeDateFormatter.format(rawDateString: trimmed)
            }
        case "my_watched_episodes":
            currentWatchedEpisodes = Int(trimmed) ?? 0
        case "my_score":
            if let score = Int(trimmed), score > 0 {
                currentScore = min(10, max(1, score))
            }
        case "my_status":
            currentStatusRaw = trimmed
        case "my_comments":
            currentComments = trimmed
        case "anime":
            if let malID = currentMalID, !currentTitle.isEmpty {
                let mappedStatus = mapStatus(currentStatusRaw)
                let entry = MALImportEntry(
                    malID: malID,
                    title: currentTitle,
                    status: mappedStatus,
                    watchedEpisodes: currentWatchedEpisodes,
                    totalEpisodes: currentTotalEpisodes,
                    userRating: currentScore,
                    personalNotes: currentComments,
                    airingStatusRaw: currentSeriesStatus,
                    seriesStart: currentSeriesStart
                )
                entries.append(entry)
            }
        default:
            break
        }
    }

    private func mapStatus(_ raw: String) -> WatchStatus {
        let lower = raw.lowercased()
        if lower.contains("completed") || raw == "2" {
            return .completed
        } else if lower.contains("watching") || raw == "1" {
            return .watching
        } else if lower.contains("plan") || raw == "6" {
            return .planToWatch
        } else if lower.contains("hold") || raw == "3" {
            return .onHold
        } else if lower.contains("drop") || raw == "4" {
            return .dropped
        }
        return .planToWatch
    }
}
