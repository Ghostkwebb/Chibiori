import Foundation

public struct DubbedLanguage: Identifiable, Hashable, Codable, Sendable {
    public var id: String { code }
    public let code: String          // e.g. "EN", "JP", "HI", "ZH", "ES"
    public let name: String          // e.g. "English", "Japanese", "Hindi", "Chinese"
    public let nativeName: String    // e.g. "English", "日本語", "हिन्दी", "中文"
    public let isNativeAudio: Bool   // true for original production audio
    public let flag: String?         // Regional flag emoji helper

    public init(
        code: String,
        name: String,
        nativeName: String,
        isNativeAudio: Bool = false,
        flag: String? = nil
    ) {
        self.code = code.uppercased()
        self.name = name
        self.nativeName = nativeName
        self.isNativeAudio = isNativeAudio
        self.flag = flag
    }

    // MARK: - Known Standard Languages Catalog
    public static let standardCatalog: [DubbedLanguage] = [
        DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵"),
        DubbedLanguage(code: "EN", name: "English", nativeName: "English", isNativeAudio: false, flag: "🇬🇧"),
        DubbedLanguage(code: "HI", name: "Hindi", nativeName: "हिन्दी", isNativeAudio: false, flag: "🇮🇳"),
        DubbedLanguage(code: "ZH", name: "Chinese", nativeName: "中文", isNativeAudio: false, flag: "🇨🇳"),
        DubbedLanguage(code: "ES", name: "Spanish", nativeName: "Español", isNativeAudio: false, flag: "🇪🇸"),
        DubbedLanguage(code: "FR", name: "French", nativeName: "Français", isNativeAudio: false, flag: "🇫🇷"),
        DubbedLanguage(code: "DE", name: "German", nativeName: "Deutsch", isNativeAudio: false, flag: "🇩🇪"),
        DubbedLanguage(code: "IT", name: "Italian", nativeName: "Italiano", isNativeAudio: false, flag: "🇮🇹"),
        DubbedLanguage(code: "PT", name: "Portuguese", nativeName: "Português", isNativeAudio: false, flag: "🇧🇷"),
        DubbedLanguage(code: "KO", name: "Korean", nativeName: "한국어", isNativeAudio: false, flag: "🇰🇷"),
        DubbedLanguage(code: "RU", name: "Russian", nativeName: "Русский", isNativeAudio: false, flag: "🇷🇺"),
        DubbedLanguage(code: "AR", name: "Arabic", nativeName: "العربية", isNativeAudio: false, flag: "🇸🇦"),
        DubbedLanguage(code: "TL", name: "Tagalog", nativeName: "Tagalog", isNativeAudio: false, flag: "🇵🇭"),
        DubbedLanguage(code: "PL", name: "Polish", nativeName: "Polski", isNativeAudio: false, flag: "🇵🇱"),
        DubbedLanguage(code: "TH", name: "Thai", nativeName: "ไทย", isNativeAudio: false, flag: "🇹🇭"),
        DubbedLanguage(code: "ID", name: "Indonesian", nativeName: "Bahasa Indonesia", isNativeAudio: false, flag: "🇮🇩"),
        DubbedLanguage(code: "TR", name: "Turkish", nativeName: "Türkçe", isNativeAudio: false, flag: "🇹🇷"),
        DubbedLanguage(code: "VI", name: "Vietnamese", nativeName: "Tiếng Việt", isNativeAudio: false, flag: "🇻🇳"),
        DubbedLanguage(code: "NL", name: "Dutch", nativeName: "Nederlands", isNativeAudio: false, flag: "🇳🇱"),
        DubbedLanguage(code: "SV", name: "Swedish", nativeName: "Svenska", isNativeAudio: false, flag: "🇸🇪"),
        DubbedLanguage(code: "NO", name: "Norwegian", nativeName: "Norsk", isNativeAudio: false, flag: "🇳🇴"),
        DubbedLanguage(code: "DA", name: "Danish", nativeName: "Dansk", isNativeAudio: false, flag: "🇩🇰"),
        DubbedLanguage(code: "FI", name: "Finnish", nativeName: "Suomi", isNativeAudio: false, flag: "🇫🇮"),
        DubbedLanguage(code: "HU", name: "Hungarian", nativeName: "Magyar", isNativeAudio: false, flag: "🇭🇺"),
        DubbedLanguage(code: "HE", name: "Hebrew", nativeName: "עברית", isNativeAudio: false, flag: "🇮🇱"),
        DubbedLanguage(code: "CA", name: "Catalan", nativeName: "Català", isNativeAudio: false, flag: "🇪🇸")
    ]

    /// Resolves an arbitrary string (e.g. "English", "en", "japanese", "hindi", "zh", "portuguese (br)") into a structured DubbedLanguage
    public static func resolve(from rawInput: String, isNative: Bool = false) -> DubbedLanguage {
        let clean = rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()

        // Exact code match
        if let match = standardCatalog.first(where: { $0.code.lowercased() == clean }) {
            return DubbedLanguage(
                code: match.code,
                name: match.name,
                nativeName: match.nativeName,
                isNativeAudio: isNative || match.isNativeAudio,
                flag: match.flag
            )
        }

        // Name prefix or equality match
        for candidate in standardCatalog {
            let candidateLower = candidate.name.lowercased()
            if clean == candidateLower || clean.hasPrefix(candidateLower) || candidateLower.hasPrefix(clean) {
                return DubbedLanguage(
                    code: candidate.code,
                    name: candidate.name,
                    nativeName: candidate.nativeName,
                    isNativeAudio: isNative || (candidate.code == "JP" && !clean.contains("dub")),
                    flag: candidate.flag
                )
            }
        }

        // Special aliases
        if clean.contains("mandarin") || clean.contains("cantonese") || clean == "cn" {
            return DubbedLanguage(code: "ZH", name: "Chinese", nativeName: "中文", isNativeAudio: isNative, flag: "🇨🇳")
        }
        if clean == "jp" || clean == "ja" || clean.contains("nihon") {
            return DubbedLanguage(code: "JP", name: "Japanese", nativeName: "日本語", isNativeAudio: true, flag: "🇯🇵")
        }
        if clean == "hi" || clean.contains("hindustani") {
            return DubbedLanguage(code: "HI", name: "Hindi", nativeName: "हिन्दी", isNativeAudio: isNative, flag: "🇮🇳")
        }

        // Fallback custom language
        let code = String(clean.prefix(2)).uppercased()
        let name = rawInput.capitalized
        return DubbedLanguage(
            code: code.isEmpty ? "DUB" : code,
            name: name,
            nativeName: name,
            isNativeAudio: isNative,
            flag: "🌐"
        )
    }

    /// Display badge title (e.g. "JP", "EN", "HI", "ZH")
    public var badgeTitle: String {
        code
    }

    /// Descriptive tooltip text for UI
    public var tooltipText: String {
        if isNativeAudio {
            return "\(name) (Original Audio)"
        } else {
            return "Dubbed in \(name) (\(nativeName))"
        }
    }

    /// Priority for sorting badges: Original audio first, then EN, HI, ZH, ES, then alphabetical
    public var sortPriority: Int {
        if isNativeAudio { return 0 }
        switch code {
        case "EN": return 1
        case "HI": return 2
        case "ZH": return 3
        case "ES": return 4
        case "FR": return 5
        case "DE": return 6
        case "IT": return 7
        case "PT": return 8
        case "KO": return 9
        default: return 10
        }
    }
}
