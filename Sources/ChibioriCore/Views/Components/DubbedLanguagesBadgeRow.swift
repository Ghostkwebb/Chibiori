import SwiftUI

/// Reusable wrapped badge strip showing native and dubbed audio languages, with an optional edit affordance.
public struct DubbedLanguagesBadgeRow: View {
    public let languages: [DubbedLanguage]
    public var onEditTap: (() -> Void)? = nil

    public init(languages: [DubbedLanguage], onEditTap: (() -> Void)? = nil) {
        self.languages = languages
        self.onEditTap = onEditTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            WrappingFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(languages) { lang in
                    dubPill(lang: lang)
                }

                if let onEditTap {
                    Button(action: onEditTap) {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Edit Dubbed Languages")
                }
            }
        }
        .padding(.top, 1)
    }

    private func dubPill(lang: DubbedLanguage) -> some View {
        HStack(spacing: 2) {
            Text(lang.code)
                .font(.system(size: 9.5, weight: lang.isNativeAudio ? .bold : .medium, design: .rounded))
            if lang.isNativeAudio {
                Circle()
                    .fill(Color.purple.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            lang.isNativeAudio
                ? Color.purple.opacity(0.25)
                : Color.white.opacity(0.1)
        )
        .foregroundStyle(lang.isNativeAudio ? Color.purple.opacity(0.95) : Color.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                lang.isNativeAudio ? Color.purple.opacity(0.4) : Color.white.opacity(0.12),
                lineWidth: 0.6
            )
        )
        .help(lang.tooltipText)
    }
}
