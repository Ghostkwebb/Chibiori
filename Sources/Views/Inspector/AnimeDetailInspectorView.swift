import SwiftUI
import SwiftData

@MainActor
public struct AnimeDetailInspectorView: View {
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext
    @Bindable var anime: TrackedAnime
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showCustomTitleEditor = false
    @State private var tempCustomTitle = ""
    @State private var isEditingNotes = false

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
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 440)
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

                if let releaseDate = anime.seasonYearFormatted {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(releaseDate)
                            .font(.system(size: 11, weight: .medium))
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
            Text("ANIME DETAILS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

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
                if let day = anime.broadcastDayRaw {
                    metadataRow(label: "Broadcast", value: day)
                }
                if !anime.genres.isEmpty {
                    metadataRow(label: "Genres", value: anime.genres.joined(separator: ", "))
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
}
