import SwiftUI

public struct GridSizeControlPopover: View {
    @Binding var gridCardSize: Double

    public init(gridCardSize: Binding<Double>) {
        self._gridCardSize = gridCardSize
    }

    private let presets: [(label: String, size: Double)] = [
        ("Small", 120),
        ("Default", 165),
        ("Large", 210),
        ("Hero", 260)
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Grid Poster Size", systemImage: "circle.grid.2x2")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(Int(gridCardSize)) pt")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Slider
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Slider(
                    value: $gridCardSize,
                    in: 110...260,
                    step: 5
                )
                .controlSize(.small)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Quick Preset Pills
            HStack(spacing: 6) {
                ForEach(presets, id: \.label) { preset in
                    let isSelected = abs(gridCardSize - preset.size) < 8
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            gridCardSize = preset.size
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassPill(tint: isSelected ? .accentColor : .secondary, isSelected: isSelected)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.3)

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Default (165pt)") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        gridCardSize = 165
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}
