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

    @FocusState private var isListFocused: Bool

    private var completedAnime: [TrackedAnime] {
        trackedAnimes.filter { $0.watchStatus == .completed }
    }

    private var existingIDs: Set<Int> {
        Set(trackedAnimes.map { $0.malID })
    }

    private var trackedMap: [Int: TrackedAnime] {
        Dictionary(uniqueKeysWithValues: trackedAnimes.map { ($0.malID, $0) })
    }

    private var displayedAlerts: [SequelAlertItem] {
        service.alerts.filter { alert in
            !existingIDs.contains(alert.sequelMalId) && !addedSequels.contains(alert.sequelMalId)
        }
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header Banner
                        headerCard
                            .padding(16)
                            .glassCard(cornerRadius: 18)

                        if service.isScanning {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                Text("Scanning upcoming sequels for your completed anime...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(14)
                            .glassCard(cornerRadius: 12)
                        }

                        if displayedAlerts.isEmpty && !service.isScanning {
                            VStack(spacing: 12) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text(service.alerts.isEmpty ? "No Upcoming Sequels Found" : "All Caught Up!")
                                    .font(.system(size: 15, weight: .bold))
                                Text(service.alerts.isEmpty
                                     ? "When a new season is announced for any anime in your Completed list, it will appear here."
                                     : "You've added all currently announced upcoming sequels to your library!")
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
                        } else if !displayedAlerts.isEmpty {
                            // List of Sequel Alerts
                            LazyVStack(spacing: 14) {
                                ForEach(displayedAlerts) { alert in
                                    let isSelected = navState.selectedJikanDTO?.malId == alert.sequelMalId ||
                                                     (trackedMap[alert.sequelMalId] != nil && trackedMap[alert.sequelMalId]?.persistentModelID == navState.selectedAnimeID)

                                    SequelAlertCard(
                                        alert: alert,
                                        languagePreference: navState.titleLanguagePreference,
                                        isSelected: isSelected,
                                        onSelect: {
                                            isListFocused = true
                                            selectAlert(alert)
                                        },
                                        onAdd: {
                                            trackSequel(alert)
                                        }
                                    )
                                    .id(alert.sequelMalId)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .smooth120HzScroll()
                .focusable()
                .focused($isListFocused)
                .focusEffectDisabled()
                .onAppear {
                    isListFocused = true
                }
                .onTapGesture {
                    isListFocused = true
                }
                .onKeyPress(.downArrow) {
                    selectDelta(1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectDelta(-1, proxy: proxy)
                    return .handled
                }
            }
        }
        .navigationTitle("Sequel & Season 2 Alerts")
        .navigationSubtitle("\(displayedAlerts.count) Upcoming Announcements")
        .onAppear {
            if service.alerts.isEmpty && !completedAnime.isEmpty {
                scanNow()
            }
        }
    }

    @MainActor
    private func selectAlert(_ alert: SequelAlertItem) {
        if let tracked = trackedMap[alert.sequelMalId] {
            navState.selectTracked(tracked.persistentModelID)
        } else {
            navState.selectDTO(alert.asJikanDTO)
            Task {
                if let details = try? await JikanAPIService.shared.fetchAnimeDetails(id: alert.sequelMalId) {
                    if navState.selectedJikanDTO?.malId == alert.sequelMalId {
                        navState.selectedJikanDTO = details
                    }
                }
            }
        }
    }

    @MainActor
    private func selectDelta(_ delta: Int, proxy: ScrollViewProxy) {
        let alerts = displayedAlerts
        guard !alerts.isEmpty else { return }

        let currentMalID = navState.selectedJikanDTO?.malId ??
                           trackedMap.first(where: { $0.value.persistentModelID == navState.selectedAnimeID })?.key ?? -1

        let currentIndex = alerts.firstIndex(where: { $0.sequelMalId == currentMalID }) ?? -1
        var nextIndex = currentIndex + delta
        if currentIndex == -1 {
            nextIndex = delta >= 0 ? 0 : alerts.count - 1
        }
        nextIndex = max(0, min(alerts.count - 1, nextIndex))
        let target = alerts[nextIndex]

        selectAlert(target)

        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(target.sequelMalId, anchor: .center)
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

            // Language Selector Picker Menu
            Menu {
                ForEach(TitleLanguagePreference.allCases) { pref in
                    Button {
                        navState.titleLanguagePreference = pref
                    } label: {
                        HStack {
                            Image(systemName: pref.icon)
                            Text(pref.displayName)
                            if navState.titleLanguagePreference == pref {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: navState.titleLanguagePreference.icon)
                    Text(navState.titleLanguagePreference.displayName)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassPill(tint: .purple, isSelected: false)
            }
            .menuStyle(.borderlessButton)

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
            englishTitle: alert.sequelEnglishTitle,
            japaneseTitle: alert.sequelJapaneseTitle,
            seasonYear: alert.airingSeasonYear
        )
        anime.watchStatus = .planToWatch
        anime.personalNotes = "Automatically added from Sequel Alert (Completed: \(alert.parentTitle))"
        modelContext.insert(anime)
        try? modelContext.save()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            addedSequels.insert(alert.sequelMalId)
            navState.selectTracked(anime.persistentModelID)
        }
    }
}

private struct SequelAlertCard: View {
    let alert: SequelAlertItem
    let languagePreference: TitleLanguagePreference
    let isSelected: Bool
    let onSelect: () -> Void
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

                Text(alert.displaySequelTitle(for: languagePreference))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text("Prequel in Library:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(alert.displayParentTitle(for: languagePreference))
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
                .padding(.top, 2)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? Color.purple.opacity(0.35) : Color.clear, radius: 10, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
