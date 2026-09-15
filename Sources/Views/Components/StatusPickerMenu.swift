import SwiftUI
import AppKit

public struct StatusPickerMenu: View {
    let currentStatus: WatchStatus
    let onSelect: (WatchStatus) -> Void

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
                    .frame(width: 6, height: 6)
                Image(systemName: currentStatus.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(currentStatus.displayName)
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(currentStatus.accentColor.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(currentStatus.accentColor.opacity(0.15))
            .foregroundStyle(currentStatus.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(currentStatus.accentColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
