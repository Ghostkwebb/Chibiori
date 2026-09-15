import SwiftUI
import SwiftData

@MainActor
public struct AnimeDetailInspectorView: View {
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext
    @Query private var allLibraryAnime: [TrackedAnime]
    @Bindable var anime: TrackedAnime
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showCustomTitleEditor = false
    @State private var tempCustomTitle = ""
    @State private var isEditingNotes = false
    @State private var isRefreshing = false
    @State private var relatedAnime: [RelatedAnimeItem] = []
    @State private var showDubEditor = false
    @State private var customLanguageInput = ""

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    public init(anime: TrackedAnime, onDelete: @escaping () -> Void) {
        self.anime = anime
        self.onDelete = onDelete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header & Large Poster
                headerSection
                    .padding(14)
                    .glassCard(cornerRadius: 16)

                // Related Seasons (Prequels / Sequels)
                if !relatedAnime.isEmpty {
                    RelatedSeasonsCardView(
                        relatedAnime: relatedAnime,
                        currentMalID: anime.malID,
                        currentTitle: anime.title,
                        currentEnglishTitle: anime.englishTitle
                    )
                    .padding(14)
                    .glassCard(cornerRadius: 14)
                }

                // Watch Status & Queue Actions
                statusAndQueueSection
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                // Episode Progress
                progressSection
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                // Rating Section
                ratingSection
                    .padding(14)
                    .glassCard(cornerRadius: 16)

                // Personal Notes Section
                notesSection
                    .padding(14)
                    .glassCard(cornerRadius: 16)

                // Synopsis Section
                synopsisSection
                    .padding(14)
                    .glassCard(cornerRadius: 16)

                // Metadata Details Section
                metadataSection
                    .padding(14)
                    .glassCard(cornerRadius: 16)

                // Delete Action
                deleteSection
                    .padding(.top, 4)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCustomTitleEditor) {
            VStack(spacing: 16) {
                Text("Set Custom Anime Title")
                    .font(.system(size: 15, weight: .bold))

                Text("Enter a custom title to display for this anime across your library, or clear it to use the default title.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Custom Title (e.g. Lord of the Mysteries)", text: $tempCustomTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Clear Override") {
                        anime.customTitleOverride = nil
                        showCustomTitleEditor = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") {
                        showCustomTitleEditor = false
                    }
                    .buttonStyle(.plain)

                    Button("Save Title") {
                        let trimmed = tempCustomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        anime.customTitleOverride = trimmed.isEmpty ? nil : trimmed
                        showCustomTitleEditor = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(20)
            .frame(width: 380)
        }
        .sheet(isPresented: $showDubEditor) {
            dubEditorSheet
        }
        .confirmationDialog(
            "Delete Anime",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete from Library", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \"\(anime.title)\" from your local library? This action cannot be undone.")
        }
        .task(id: anime.malID) {
            var rels = await AnimeRelationsService.shared.fetchRelations(for: anime.malID, title: anime.title)
            if rels.isEmpty {
                let library = !allLibraryAnime.isEmpty ? allLibraryAnime : ((try? modelContext.fetch(FetchDescriptor<TrackedAnime>())) ?? [])
                rels = AnimeRelationsService.shared.discoverLibraryFranchiseRelations(for: anime, allLibrary: library)
            }
            relatedAnime = rels
            let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID)
            if !dubs.isEmpty {
                let existingLower = Set(anime.dubbedLanguages.map { $0.lowercased() })
                let newNames = dubs.map { $0.name }
                if anime.dubbedLanguages.isEmpty || (!existingLower.contains("english") && newNames.contains("English")) {
                    var merged = anime.dubbedLanguages
                    for name in newNames where !existingLower.contains(name.lowercased()) {
                        merged.append(name)
                    }
                    if merged != anime.dubbedLanguages {
                        anime.dubbedLanguages = merged
                        try? modelContext.save()
                    }
                }
            }
        }
        .onChange(of: allLibraryAnime) { _, newLibrary in
            if relatedAnime.isEmpty && !newLibrary.isEmpty {
                let localRels = AnimeRelationsService.shared.discoverLibraryFranchiseRelations(for: anime, allLibrary: newLibrary)
                if !localRels.isEmpty {
                    relatedAnime = localRels
                }
            }
        }
    }

    // MARK: - Header & Large Poster Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            // Large Poster Art
            CachedCoverImage(
                malID: anime.malID,
                remoteURLString: anime.coverImageRemoteURL,
                localFilename: anime.coverImageFilename,
                cornerRadius: 12,
                shadowRadius: 8
            )
            .frame(width: 120, height: 170)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

            // Title & Highlights
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.displayTitle(for: navState.titleLanguagePreference))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Title Language Variant Quick-Pills
                HStack(spacing: 5) {
                    ForEach(TitleLanguagePreference.allCases) { pref in
                        let titleVal = anime.displayTitle(for: pref)
                        Button {
                            navState.titleLanguagePreference = pref
                        } label: {
                            Text(pref.shortName)
                                .font(.system(size: 9.5, weight: navState.titleLanguagePreference == pref ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    navState.titleLanguagePreference == pref ?
                                    Color.purple.opacity(0.4) :
                                    Color.white.opacity(0.1)
                                )
                                .foregroundStyle(navState.titleLanguagePreference == pref ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(pref.displayName): \(titleVal)")
                    }

                    Button {
                        tempCustomTitle = anime.customTitleOverride ?? anime.displayTitle(for: navState.titleLanguagePreference)
                        showCustomTitleEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .padding(4)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit custom title override")

                    Button {
                        Task {
                            await refreshAllData(forceRefreshRelations: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .rotationEffect(isRefreshing ? .degrees(360) : .degrees(0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            .padding(4)
                            .background(Color.purple.opacity(0.25))
                            .clipShape(Circle())
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .help("Refresh anime status, episode count, score, relations & metadata")
                }
                .padding(.vertical, 2)

                // Score & Airing Status Badges
                HStack(spacing: 6) {
                    if let score = anime.malScore {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                    }

                    AiringStatusBadge(status: anime.airingStatus)
                }
                .padding(.top, 2)

                if let dates = anime.airingDatesDisplay {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .padding(.top, 1)
                        Text(dates)
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                }

                if let episodes = anime.totalEpisodes {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                        Text("\(episodes) Episodes")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }

                dubbedLanguagesHeaderRow
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Watch Status & Queue Section
    private var statusAndQueueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WATCH STATUS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack {
                StatusPickerMenu(currentStatus: anime.watchStatus) { newStatus in
                    withAnimation(.spring(response: 0.3)) {
                        anime.setWatchStatus(newStatus)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        anime.reQueue()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Re-Queue")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassPill(tint: .purple, isSelected: false)
                }
                .buttonStyle(.plain)
                .help("Move to top of list and refresh date added")
            }
        }
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EPISODE PROGRESS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(anime.currentEpisodeProgress) / \(anime.totalEpisodes.map { String($0) } ?? "?")")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            // Progress Bar
            if let total = anime.totalEpisodes, total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geo.size.width * min(1.0, CGFloat(anime.currentEpisodeProgress) / CGFloat(total)),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    if anime.currentEpisodeProgress > 0 {
                        anime.currentEpisodeProgress -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 24)
                        .glassPill(tint: .secondary, isSelected: false)
                }
                .buttonStyle(.plain)
                .disabled(anime.currentEpisodeProgress <= 0)

                Button {
                    anime.incrementProgress()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("+1 Episode")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .glassPill(tint: .accentColor, isSelected: false)
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)

                if let total = anime.totalEpisodes, anime.currentEpisodeProgress < total {
                    Button("Finish") {
                        withAnimation(.spring(response: 0.3)) {
                            anime.currentEpisodeProgress = total
                            anime.setWatchStatus(.completed)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Rating Section
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR RATING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if let rating = anime.userRating {
                    Text("\(rating) / 10")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.yellow)
                } else {
                    Text("Unrated")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            RatingStarPicker(rating: $anime.userRating)
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PERSONAL NOTES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TextEditor(text: $anime.personalNotes)
                .font(.system(size: 12))
                .frame(minHeight: 55, maxHeight: 110)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Synopsis Section
    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNOPSIS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(anime.synopsis.isEmpty ? "No synopsis available." : anime.synopsis)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ANIME DETAILS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await refreshAllData(forceRefreshRelations: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(isRefreshing ? .degrees(360) : .degrees(0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        Text(isRefreshing ? "Refreshing..." : "Refresh Details")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassPill(tint: .purple, isSelected: false)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            VStack(spacing: 6) {
                if let en = anime.englishTitle, !en.isEmpty {
                    metadataRow(label: "English", value: en)
                }
                metadataRow(label: "Romaji", value: anime.title)
                if let jp = anime.japaneseTitle, !jp.isEmpty {
                    metadataRow(label: "Native", value: jp)
                }
                if let custom = anime.customTitleOverride, !custom.isEmpty {
                    metadataRow(label: "Custom", value: custom)
                }
                Divider().opacity(0.3)
                metadataRow(label: "MAL ID", value: "\(anime.malID)")
                if let score = anime.malScore {
                    metadataRow(label: "MAL Score", value: String(format: "%.2f", score))
                }
                if let releaseDate = anime.seasonYearFormatted {
                    metadataRow(label: "Release Date", value: releaseDate)
                }
                if let ended = anime.airingEndDateFormatted, anime.airingStatus == .finishedAiring {
                    metadataRow(label: "Ended", value: ended)
                }
                if let day = anime.broadcastDayRaw {
                    metadataRow(label: "Broadcast", value: day)
                }
                if !anime.genres.isEmpty {
                    metadataRow(label: "Genres", value: anime.genres.joined(separator: ", "))
                }
                if !anime.resolvedDubbedLanguages.isEmpty {
                    metadataRow(label: "Dubbed In", value: anime.dubbedLanguagesDisplay)
                }
                Divider().opacity(0.3)
                metadataRow(label: "Added", value: Self.dateFormatter.string(from: anime.dateAdded))
                if let started = anime.dateStarted {
                    metadataRow(label: "Started", value: Self.dateFormatter.string(from: started))
                }
                if let completed = anime.dateCompleted {
                    metadataRow(label: "Completed", value: Self.dateFormatter.string(from: completed))
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Delete Section
    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text("Remove from Library")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.12))
            .foregroundStyle(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dubbed Languages Header Row
    private var dubbedLanguagesHeaderRow: some View {
        let langs = anime.resolvedDubbedLanguages
        return HStack(alignment: .top, spacing: 5) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            WrappingFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(langs) { lang in
                    dubPill(lang: lang)
                }

                Button {
                    showDubEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit or add dubbed languages")
            }
        }
        .padding(.top, 1)
    }

    private func dubPill(lang: DubbedLanguage) -> some View {
        HStack(spacing: 2) {
            Text(lang.code)
                .font(.system(size: 9.5, weight: lang.isNativeAudio ? .bold : .medium, design: .rounded))
            if lang.isNativeAudio {
                Circle()
                    .fill(Color.purple.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            lang.isNativeAudio ?
            Color.purple.opacity(0.25) :
            Color.white.opacity(0.1)
        )
        .foregroundStyle(lang.isNativeAudio ? Color.purple.opacity(0.95) : Color.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                lang.isNativeAudio ? Color.purple.opacity(0.4) : Color.white.opacity(0.12),
                lineWidth: 0.6
            )
        )
        .help(lang.tooltipText)
    }

    private func toggleLanguage(_ lang: DubbedLanguage) {
        if let index = anime.dubbedLanguages.firstIndex(where: { DubbedLanguage.resolve(from: $0).code == lang.code }) {
            anime.dubbedLanguages.remove(at: index)
        } else {
            anime.dubbedLanguages.append(lang.name)
        }
        try? modelContext.save()
    }

    private var dubEditorSheet: some View {
        VStack(spacing: 16) {
            Text("Manage Dubbed Languages")
                .font(.system(size: 15, weight: .bold))

            Text("Select the audio and dub tracks available for this anime, or add custom regional languages.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(DubbedLanguage.standardCatalog) { standardLang in
                        let isIncluded = anime.dubbedLanguages.contains { DubbedLanguage.resolve(from: $0).code == standardLang.code } || (standardLang.code == "JP" && anime.dubbedLanguages.isEmpty)
                        Button {
                            toggleLanguage(standardLang)
                        } label: {
                            HStack(spacing: 4) {
                                if let flag = standardLang.flag {
                                    Text(flag)
                                }
                                Text(standardLang.name)
                                if isIncluded {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .font(.system(size: 11, weight: isIncluded ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isIncluded ? Color.purple.opacity(0.35) : Color.white.opacity(0.08))
                            .foregroundStyle(isIncluded ? Color.white : Color.secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isIncluded ? Color.purple.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 180)

            HStack(spacing: 8) {
                TextField("Add custom language (e.g. Tamil, Telugu, Catalan)...", text: $customLanguageInput)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    let trimmed = customLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if !anime.dubbedLanguages.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                            anime.dubbedLanguages.append(trimmed)
                            try? modelContext.save()
                        }
                        customLanguageInput = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(customLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            HStack {
                Button("Auto-Detect Dubs") {
                    Task {
                        let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID, forceRefresh: true)
                        anime.dubbedLanguages = dubs.map { $0.name }
                        try? modelContext.save()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.purple)

                Spacer()

                Button("Done") {
                    showDubEditor = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 460, height: 390)
    }

    private func refreshAllData(forceRefreshRelations: Bool = false) async {
        isRefreshing = true
        await MetadataHydrationService.shared.refreshAnimeMetadata(anime: anime, context: modelContext)
        var rels = await AnimeRelationsService.shared.fetchRelations(for: anime.malID, title: anime.title, forceRefresh: forceRefreshRelations)
        if rels.isEmpty {
            let library = !allLibraryAnime.isEmpty ? allLibraryAnime : ((try? modelContext.fetch(FetchDescriptor<TrackedAnime>())) ?? [])
            rels = AnimeRelationsService.shared.discoverLibraryFranchiseRelations(for: anime, allLibrary: library)
        }
        relatedAnime = rels
        let dubs = await DubbedLanguageService.shared.fetchDubbedLanguages(malId: anime.malID)
        if !dubs.isEmpty {
            let existingLower = Set(anime.dubbedLanguages.map { $0.lowercased() })
            let newNames = dubs.map { $0.name }
            if anime.dubbedLanguages.isEmpty || (!existingLower.contains("english") && newNames.contains("English")) {
                var merged = anime.dubbedLanguages
                for name in newNames where !existingLower.contains(name.lowercased()) {
                    merged.append(name)
                }
                if merged != anime.dubbedLanguages {
                    anime.dubbedLanguages = merged
                    try? modelContext.save()
                }
            }
        }
        isRefreshing = false
    }
}
