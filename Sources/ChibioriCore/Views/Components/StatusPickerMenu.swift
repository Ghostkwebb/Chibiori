import SwiftUI
import AppKit

public struct StatusPickerMenu: View {
    let currentStatus: WatchStatus
    let onSelect: (WatchStatus) -> Void

    @State private var isHovered = false

    public init(currentStatus: WatchStatus, onSelect: @escaping (WatchStatus) -> Void) {
        self.currentStatus = currentStatus
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            StatusMenuPresenter.shared.presentMenu(
                currentStatus: currentStatus,
                headerTitle: "MOVE TO STATUS",
                onSelect: onSelect
            )
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(currentStatus.accentColor)
                    .frame(width: 5.5, height: 5.5)
                Image(systemName: currentStatus.systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isHovered ? currentStatus.accentColor : .secondary)
                Text(currentStatus.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.white : Color.primary.opacity(0.88))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(isHovered ? currentStatus.accentColor : Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                isHovered ?
                currentStatus.accentColor.opacity(0.20) :
                Color.white.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isHovered ?
                        currentStatus.accentColor.opacity(0.45) :
                        Color.white.opacity(0.12),
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .fixedSize()
    }
}
