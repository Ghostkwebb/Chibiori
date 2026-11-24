import SwiftUI

public struct QuickEpisodeIncrementButton: View {
    let current: Int
    let total: Int?
    let onIncrement: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    public init(current: Int, total: Int?, onIncrement: @escaping () -> Void) {
        self.current = current
        self.total = total
        self.onIncrement = onIncrement
    }

    private var isMaxReached: Bool {
        if let total = total {
            return current >= total
        }
        return false
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                isPressed = true
            }
            onIncrement()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("1")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(
                isMaxReached ? Color.white.opacity(0.04) :
                isHovered ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06)
            )
            .foregroundStyle(
                isMaxReached ? Color.secondary.opacity(0.5) :
                isHovered ? Color.white : Color.primary.opacity(0.85)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.12),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isMaxReached)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isMaxReached ? "All episodes watched" : "Mark next episode as watched (+1)")
    }
}
