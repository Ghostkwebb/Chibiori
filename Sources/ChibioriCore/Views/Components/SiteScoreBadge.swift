import SwiftUI
import AppKit

/// Crisp, non-truncating monogram badge for each anime rating platform.
public struct SiteLogoMark: View {
    public let source: ScoreSource
    public var height: CGFloat = 13

    public init(source: ScoreSource, height: CGFloat = 13) {
        self.source = source
        self.height = height
    }

    public var body: some View {
        Text(source.shortCode)
            .font(.system(size: max(7, height * 0.54), weight: .heavy, design: .rounded))
            .tracking(-0.2)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, height * 0.34)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: max(3.5, height * 0.28), style: .continuous)
                    .fill(source.brandColor)
            )
            .fixedSize()
    }
}

/// Sleek frosted glass score pill shown in the top-right corner of anime cards and table rows.
public struct SiteScoreCardPill: View {
    public let source: ScoreSource
    public let score: Double
    public var fontSize: CGFloat = 9.5
    public var logoHeight: CGFloat = 13

    public init(
        source: ScoreSource,
        score: Double,
        fontSize: CGFloat = 9.5,
        logoHeight: CGFloat = 13
    ) {
        self.source = source
        self.score = score
        self.fontSize = fontSize
        self.logoHeight = logoHeight
    }

    public var body: some View {
        HStack(spacing: 4) {
            SiteLogoMark(source: source, height: logoHeight)
            Text(AnimeSiteScores.formatScore(score, for: source, compact: true))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 3)
        .padding(.trailing, 6)
        .padding(.vertical, 2.5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            Capsule().fill(source.brandColor.opacity(0.22))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.26), lineWidth: 0.6)
        )
        .fixedSize()
        .help("\(source.displayName) Score: \(AnimeSiteScores.formatScore(score, for: source)) / 10")
    }
}

/// Multi-website score strip displayed in the detail inspector, with non-truncating logos and clickable links.
public struct SiteScoresBadgeStrip: View {
    public let malID: Int
    public let siteScores: AnimeSiteScores?
    public let fallbackScore: Double?
    public let isLoading: Bool

    public init(
        malID: Int,
        siteScores: AnimeSiteScores?,
        fallbackScore: Double? = nil,
        isLoading: Bool = false
    ) {
        self.malID = malID
        self.siteScores = siteScores
        self.fallbackScore = fallbackScore
        self.isLoading = isLoading
    }

    private var displayedEntries: [(source: ScoreSource, score: Double)] {
        if let entries = siteScores?.entries, !entries.isEmpty {
            return entries
        }
        if let fallbackScore, fallbackScore > 0 {
            return [(.aniList, fallbackScore)]
        }
        return []
    }

    public var body: some View {
        if !displayedEntries.isEmpty || isLoading {
            WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(displayedEntries, id: \.source) { entry in
                    let formatted = AnimeSiteScores.formatScore(entry.score, for: entry.source)
                    let targetURL = entry.source.pageURL(
                        malID: malID,
                        aniListID: siteScores?.aniListID,
                        kitsuSlug: siteScores?.kitsuSlug
                    )

                    Button {
                        if let targetURL {
                            NSWorkspace.shared.open(targetURL)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            SiteLogoMark(source: entry.source, height: 14)
                            Text(formatted)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(entry.source.brandColor.opacity(0.14))
                        )
                        .overlay(
                            Capsule().strokeBorder(entry.source.brandColor.opacity(0.40), lineWidth: 0.8)
                        )
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help(tooltip(for: entry.source, formatted: formatted, hasLink: targetURL != nil))
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.48)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                        .help("Refreshing scores...")
                }
            }
        }
    }

    private func tooltip(for source: ScoreSource, formatted: String, hasLink: Bool) -> String {
        let linkHint = hasLink ? " — Click to open on \(source.displayName)" : ""
        if source == .aniList, let rawScore = siteScores?.aniListScore {
            let percent = Int((rawScore * 10).rounded())
            return "AniList Score: \(formatted) / 10 (\(percent)%)\(linkHint)"
        }
        return "\(source.displayName) Score: \(formatted) / 10\(linkHint)"
    }
}
