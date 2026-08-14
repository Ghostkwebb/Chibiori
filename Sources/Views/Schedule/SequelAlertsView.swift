import SwiftUI
import SwiftData

@MainActor
public struct SequelAlertsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trackedAnimes: [TrackedAnime]
    @Environment(NavigationState.self) private var navState

    @State private var service = SequelAlertService.shared
    @State private var addedSequels: Set<Int> = []

    public init() {}

    private var completedAnime: [TrackedAnime] {
        trackedAnimes.filter { $0.watchStatus == .completed }
    }

    private var existingIDs: Set<Int> {
        Set(trackedAnimes.map { $0.malID })
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Banner
                    headerCard
                        .padding(16)
                        .glassCard(cornerRadius: 18)

                    if service.isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Checking upcoming sequels for your completed anime...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .glassCard(cornerRadius: 16)
                    } else if service.alerts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No Upcoming Sequels Found")
                                .font(.system(size: 15, weight: .bold))
                            Text("When a new season is announced for any anime in your Completed list, it will appear here.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                scanNow()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan Completed Anime Now")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .glassCard(cornerRadius: 16)
                    } else {
                        // Grid of Sequel Alerts
                        LazyVStack(spacing: 14) {
                            ForEach(service.alerts) { alert in
                                SequelAlertCard(
                                    alert: alert,
                                    isAlreadyAdded: addedSequels.contains(alert.sequelMalId) || existingIDs.contains(alert.sequelMalId)
                                ) {
                                    trackSequel(alert)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .smooth120HzScroll()
        }
        .navigationTitle("Sequel & Season 2 Alerts")
        .navigationSubtitle("\(service.alerts.count) Upcoming Announcements")
        .onAppear {
            if service.alerts.isEmpty && !completedAnime.isEmpty {
                scanNow()
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 28))
                .foregroundStyle(.purple)
                .frame(width: 48, height: 48)
                .background(Color.purple.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("AUTOMATIC SEQUEL NOTIFICATIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)

                Text("New Season Announcements for Completed Anime")
                    .font(.system(size: 14, weight: .bold))

                Text("Chibiori checks MyAnimeList & AniList for newly announced seasons or movies related to anime you've completed.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                scanNow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassPill(tint: .purple, isSelected: false)
            }
            .buttonStyle(.plain)
            .disabled(service.isScanning)
        }
    }

    private func scanNow() {
        Task {
            await service.scanForSequels(completedAnime: completedAnime, existingTrackedIDs: existingIDs)
        }
    }

    private func trackSequel(_ alert: SequelAlertItem) {
        let anime = TrackedAnime(
            malID: alert.sequelMalId,
            title: alert.sequelTitle,
            synopsis: alert.synopsis ?? "",
            coverImageRemoteURL: alert.sequelCoverImageURL,
            airingStatusRaw: alert.sequelStatus == "RELEASING" ? "Currently Airing" : "Not Yet Airing",
            seasonYear: alert.airingSeasonYear
        )
        anime.watchStatus = .planToWatch
        anime.personalNotes = "Automatically added from Sequel Alert (Completed: \(alert.parentTitle))"
        modelContext.insert(anime)
        try? modelContext.save()

        addedSequels.insert(alert.sequelMalId)
    }
}

private struct SequelAlertCard: View {
    let alert: SequelAlertItem
    let isAlreadyAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Sequel Poster
            CachedCoverImage(
                malID: alert.sequelMalId,
                remoteURLString: alert.sequelCoverImageURL,
                cornerRadius: 10,
                shadowRadius: 4
            )
            .frame(width: 80, height: 115)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
            )

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("SEQUEL ANNOUNCED")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.18))
                        .clipShape(Capsule())

                    if let airing = alert.airingSeasonYear {
                        Text(airing)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(alert.sequelTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text("Prequel in Library:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(alert.parentTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.9))
                }

                if let syn = alert.synopsis, !syn.isEmpty {
                    Text(syn)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Spacer()

                    if isAlreadyAdded {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("In Library (Plan to Watch)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button {
                            onAdd()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to Plan to Watch")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassPill(tint: .purple, isSelected: false)
                            .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
}
