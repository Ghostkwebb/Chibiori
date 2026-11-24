import SwiftUI

struct LibraryStatsCard: View {
    let totalCount: Int
    let watchingCount: Int
    let completedCount: Int
    let totalEpisodesWatched: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOCAL LIBRARY OVERVIEW")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statTile(label: "Total Anime", value: "\(totalCount)", icon: "film.stack", color: .blue)
                statTile(label: "Watching", value: "\(watchingCount)", icon: "play.circle.fill", color: .green)
                statTile(label: "Completed", value: "\(completedCount)", icon: "checkmark.seal.fill", color: .purple)
                statTile(label: "Episodes Watched", value: "\(totalEpisodesWatched)", icon: "tv.fill", color: .orange)
            }
        }
    }

    private func statTile(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(0.3), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
