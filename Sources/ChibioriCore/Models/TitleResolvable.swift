import Foundation

/// Shared protocol for anime models and DTOs that provide romaji, English, and native titles.
public protocol TitleResolvable {
    var primaryRomajiTitle: String { get }
    var optionalEnglishTitle: String? { get }
    var optionalNativeTitle: String? { get }
    var titleOverride: String? { get }
}

extension TitleResolvable {
    public var titleOverride: String? { nil }

    /// Resolves the preferred title with graceful fallback across English -> Romaji -> Native.
    public func resolveDisplayTitle(for preference: TitleLanguagePreference = .english, fallback: String = "Untitled Anime") -> String {
        if let custom = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }

        let en = optionalEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ro = primaryRomajiTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let jp = optionalNativeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch preference {
        case .english:
            if let en, !en.isEmpty { return en }
            if !ro.isEmpty { return ro }
            if let jp, !jp.isEmpty { return jp }
            return fallback
        case .romaji:
            if !ro.isEmpty { return ro }
            if let en, !en.isEmpty { return en }
            if let jp, !jp.isEmpty { return jp }
            return fallback
        case .native:
            if let jp, !jp.isEmpty { return jp }
            if !ro.isEmpty { return ro }
            if let en, !en.isEmpty { return en }
            return fallback
        }
    }

    public var resolvedTitleVariants: [(preference: TitleLanguagePreference, title: String)] {
        var list: [(TitleLanguagePreference, String)] = []
        if let en = optionalEnglishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
            list.append((.english, en))
        }
        let ro = primaryRomajiTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ro.isEmpty {
            list.append((.romaji, ro))
        }
        if let jp = optionalNativeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jp.isEmpty {
            list.append((.native, jp))
        }
        return list
    }
}
