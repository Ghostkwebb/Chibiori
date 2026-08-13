import SwiftUI

// MARK: - Glass Surface Modifiers

public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var isHovered: Bool = false
    var isSelected: Bool = false
    var tintColor: Color? = nil

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.68))

                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.4)]
                                : isHovered
                                    ? [Color.white.opacity(0.4), Color.white.opacity(0.15)]
                                    : [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1.8 : 1.0
                    )
            )
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.35)
                    : Color.black.opacity(0.16),
                radius: isSelected ? 6 : 4,
                x: 0,
                y: 2
            )
    }
}

public struct GlassPillModifier: ViewModifier {
    var tint: Color = .accentColor
    var isSelected: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))

                    Capsule(style: .continuous)
                        .fill(isSelected ? tint.opacity(0.9) : tint.opacity(0.12))
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.white.opacity(0.6), Color.white.opacity(0.2)]
                                : [tint.opacity(0.5), tint.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(
                color: isSelected ? tint.opacity(0.35) : Color.clear,
                radius: 6,
                x: 0,
                y: 2
            )
    }
}

// MARK: - Ambient Background (Hardware Accelerated for Smooth 120 FPS Resizing)

public struct AmbientGlowBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.purple.opacity(0.09),
                    Color.clear,
                    Color.blue.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - View Extensions

extension View {
    public func glassCard(
        cornerRadius: CGFloat = 12,
        isHovered: Bool = false,
        isSelected: Bool = false,
        tintColor: Color? = nil
    ) -> some View {
        self.modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            isHovered: isHovered,
            isSelected: isSelected,
            tintColor: tintColor
        ))
    }

    public func glassPill(tint: Color = .accentColor, isSelected: Bool = false) -> some View {
        self.modifier(GlassPillModifier(tint: tint, isSelected: isSelected))
    }
}
