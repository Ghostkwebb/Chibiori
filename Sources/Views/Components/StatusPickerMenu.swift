import SwiftUI

public struct StatusPickerMenu: View {
    let currentStatus: WatchStatus
    let onSelect: (WatchStatus) -> Void

    public init(currentStatus: WatchStatus, onSelect: @escaping (WatchStatus) -> Void) {
        self.currentStatus = currentStatus
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            Section("MOVE TO STATUS") {
                ForEach(WatchStatus.allCases) { status in
                    Button {
                        onSelect(status)
                    } label: {
                        if currentStatus == status {
                            Label("\(status.displayName)  ✓", systemImage: status.systemImage)
                        } else {
                            Label(status.displayName, systemImage: status.systemImage)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
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
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
