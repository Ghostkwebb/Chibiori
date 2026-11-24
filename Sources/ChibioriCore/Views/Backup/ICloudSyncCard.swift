import SwiftUI

struct ICloudSyncCard: View {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    let onSyncNow: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ICLOUD DRIVE AUTO-SYNC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(CloudSyncService.shared.syncStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CloudSyncService.shared.isSyncing ? .orange : .cyan)
                }

                Spacer()

                if CloudSyncService.shared.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                } else {
                    Button(action: onSyncNow) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise.icloud.fill")
                            Text("Sync Now")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassPill(tint: .cyan, isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Your anime library is automatically saved to your iCloud Drive (~/iCloud Drive/Chibiori/Chibiori_CloudSync.json). If you wipe this Mac and sign back in with the same Apple ID, Chibiori will restore your full library on first launch — no developer account required.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 12) {
                if let lastSync = CloudSyncService.shared.lastCloudSyncDate {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Last sync: \(Self.dateFormatter.string(from: lastSync))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onRevealInFinder) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("Open in Finder")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassPill(tint: .secondary, isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
