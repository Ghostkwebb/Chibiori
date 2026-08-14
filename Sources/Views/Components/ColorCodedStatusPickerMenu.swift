import SwiftUI
import AppKit

public struct ColorCodedStatusPickerMenu: View {
    let currentStatus: WatchStatus?
    let title: String
    let onSelect: (WatchStatus) -> Void

    public init(
        currentStatus: WatchStatus? = nil,
        title: String = "Track Anime",
        onSelect: @escaping (WatchStatus) -> Void
    ) {
        self.currentStatus = currentStatus
        self.title = title
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            Section("ADD TO WATCH STATUS") {
                ForEach(WatchStatus.allCases) { status in
                    Button {
                        onSelect(status)
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: status.coloredMenuIcon)
                            if currentStatus == status {
                                Text("\(status.displayName)  ✓")
                            } else {
                                Text(status.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let status = currentStatus {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                    Text(status.displayName)
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(currentStatus != nil ? currentStatus!.accentColor.opacity(0.8) : Color.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if let status = currentStatus {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(status.accentColor.opacity(0.15))
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        currentStatus != nil ? currentStatus!.accentColor.opacity(0.35) : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(currentStatus != nil ? currentStatus!.accentColor : Color.white)
        }
        .menuStyle(.borderlessButton)
    }
}
