import Foundation

/// Thread-safe HTML stripping and basic entity decoding using precompiled regexes.
public enum HTMLCleaner: Sendable {
    private static let breakRegex = try! NSRegularExpression(
        pattern: #"<br\s*/?>"#,
        options: .caseInsensitive
    )
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"<[^>]+>"#,
        options: .caseInsensitive
    )

    private static let entities: [(String, String)] = [
        ("&quot;", "\""),
        ("&#039;", "'"),
        ("&apos;", "'"),
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&nbsp;", " ")
    ]

    /// Strips HTML break/tag markup and decodes common entities into clean plain text.
    public static func strip(from html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        let mutable = NSMutableString(string: html)
        breakRegex.replaceMatches(
            in: mutable,
            options: [],
            range: NSRange(location: 0, length: mutable.length),
            withTemplate: "\n"
        )
        tagRegex.replaceMatches(
            in: mutable,
            options: [],
            range: NSRange(location: 0, length: mutable.length),
            withTemplate: ""
        )
        var text = String(mutable)
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        let cleaned = text
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
