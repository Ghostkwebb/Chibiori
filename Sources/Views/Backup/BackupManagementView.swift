import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

public enum MALImportFilterOption: String, CaseIterable, Identifiable {
    case completedOnly = "Completed Only"
    case watchingOnly = "Watching Only"
    case planToWatchOnly = "Plan to Watch Only"
    case allStatuses = "All Statuses"

    public var id: String { rawValue }

    public var allowedSet: Set<WatchStatus>? {
        switch self {
        case .completedOnly:
            return [.completed]
        case .watchingOnly:
            return [.watching]
        case .planToWatchOnly:
            return [.planToWatch]
        case .allStatuses:
            return nil
        }
    }
}

@MainActor
public struct BackupManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAnime: [TrackedAnime]

    @State private var exportMessage: String? = nil
    @State private var importMessage: String? = nil
    @State private var malImportMessage: String? = nil
    @State private var selectedMALFilter: MALImportFilterOption = .completedOnly
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isMALImporting = false
    @State private var showClearCacheAlert = false
    @State private var clearCacheMessage: String? = nil

    public init() {}

    private var totalEpisodesWatched: Int {
        allAnime.reduce(0) { $0 + $1.currentEpisodeProgress }
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Overview stats
                    libraryStatsCard
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // Apple iCloud & CloudKit Synchronization Card
                    iCloudSyncCard
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // MyAnimeList (MAL) XML Import Section
                    malImportSection
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // JSON Backup Export Section
                    exportSection
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // JSON Backup Import Section
                    importSection
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // Maintenance & Cache Section
                    maintenanceSection
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                    // Software Update Section
                    updateSection
                        .padding(18)
                        .glassCard(cornerRadius: 18)
                }
                .padding(20)
            }
        }
        .navigationTitle("Import / Export JSON & MAL")
        .alert("Clear Cover Cache", isPresented: $showClearCacheAlert) {
            Button("Clear Cache", role: .destructive) {
                Task {
                    await CoverImageManager.shared.clearCache()
                    clearCacheMessage = "Covers cache cleared successfully."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded poster images from Application Support/Chibiori/Covers. They will be re-downloaded on demand.")
        }
    }

    // MARK: - Stats Card
    private var libraryStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOCAL LIBRARY OVERVIEW")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statTile(label: "Total Anime", value: "\(allAnime.count)", icon: "film.stack", color: .blue)
                statTile(label: "Watching", value: "\(allAnime.filter { $0.watchStatus == .watching }.count)", icon: "play.circle.fill", color: .green)
                statTile(label: "Completed", value: "\(allAnime.filter { $0.watchStatus == .completed }.count)", icon: "checkmark.seal.fill", color: .purple)
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

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    // MARK: - iCloud Sync Card
    private var iCloudSyncCard: some View {
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
                    Button {
                        CloudSyncService.shared.performAutoCloudBackup(from: allAnime)
                    } label: {
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

                Button {
                    CloudSyncService.shared.revealInFinder()
                } label: {
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

    // MARK: - MyAnimeList XML Import Section
    private var malImportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.purple)
                Text("MYANIMELIST (MAL) XML IMPORT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Text("Export your list from MyAnimeList (Export panel at myanimelist.net/panel.php?go=export) and upload the XML file here. You can choose to import only your Completed anime or all list statuses.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            // Status Filter Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Import Filter:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(MALImportFilterOption.allCases) { option in
                        let isSelected = selectedMALFilter == option
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                selectedMALFilter = option
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(option.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassPill(tint: isSelected ? .purple : .secondary, isSelected: isSelected)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let missingCoversCount = allAnime.filter { $0.coverImageRemoteURL.isEmpty }.count

            HStack(spacing: 12) {
                Button {
                    importMALXMLFile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Select & Import MAL XML File...")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isMALImporting || MetadataHydrationService.shared.isHydrating)

                if missingCoversCount > 0 {
                    Button {
                        Task {
                            await MetadataHydrationService.shared.hydrateMissingMetadata(context: modelContext)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down")
                            Text("Fetch Missing Posters (\(missingCoversCount))")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(MetadataHydrationService.shared.isHydrating)
                }
            }

            if MetadataHydrationService.shared.isHydrating {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: MetadataHydrationService.shared.currentProgress)
                        .progressViewStyle(.linear)
                    Text(MetadataHydrationService.shared.statusMessage ?? "Fetching poster artwork...")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.purple)
                }
                .padding(.top, 4)
            } else if let malImportMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(malImportMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Export Section
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPORT CHIBIORI BACKUP")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            Text("Export your entire local library as a standardized JSON backup file. All queue ordering, custom ratings, personal notes, and timestamps are preserved.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                exportBackupFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Library to JSON...")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(isExporting)

            if let exportMessage {
                Text(exportMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Import Section
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMPORT CHIBIORI JSON BACKUP")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            Text("Import records from a previous Chibiori JSON backup file.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                importBackupFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Backup JSON...")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(isImporting)

            if let importMessage {
                Text(importMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Maintenance Section
    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STORAGE & MAINTENANCE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            Text("Poster images are stored locally in Application Support/Chibiori/Covers for instant offline access.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear Poster Image Cache")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)

            if let clearCacheMessage {
                Text(clearCacheMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helper File Panel Handlers
    private func importMALXMLFile() {
        isMALImporting = true
        malImportMessage = nil

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.xml, UTType(filenameExtension: "xml") ?? .xml]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let summary = try BackupService.shared.importMALXML(
                        data: data,
                        allowedStatuses: selectedMALFilter.allowedSet,
                        context: modelContext
                    )
                    malImportMessage = "Successfully imported \(summary.insertedCount) new anime and updated \(summary.updatedCount) entries from your MyAnimeList XML! (Filter: \(selectedMALFilter.rawValue))"

                    // Automatically fetch missing cover images & metadata in background
                    Task {
                        await MetadataHydrationService.shared.hydrateMissingMetadata(context: modelContext)
                    }
                } catch {
                    malImportMessage = "Failed to parse MAL XML: \(error.localizedDescription)"
                }
            }
            isMALImporting = false
        }
    }

    private func exportBackupFile() {
        isExporting = true
        exportMessage = nil

        do {
            let data = try BackupService.shared.generateExportData(from: allAnime)

            let savePanel = NSSavePanel()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: Date())
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = "Chibiori_Backup_\(dateStr).json"
            savePanel.canCreateDirectories = true

            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try data.write(to: url, options: .atomic)
                        exportMessage = "Successfully exported \(allAnime.count) anime records to \(url.lastPathComponent)."
                    } catch {
                        exportMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
                isExporting = false
            }
        } catch {
            exportMessage = "Failed to encode backup data: \(error.localizedDescription)"
            isExporting = false
        }
    }

    private func importBackupFile() {
        isImporting = true
        importMessage = nil

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let summary = try BackupService.shared.importBackup(data: data, context: modelContext)
                    importMessage = "Import completed! Parsed: \(summary.totalParsed), Added: \(summary.insertedCount), Updated: \(summary.updatedCount)."
                } catch {
                    importMessage = "Failed to import JSON: \(error.localizedDescription)"
                }
            }
            isImporting = false
        }
    }

    // MARK: - Software Update Section
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("SOFTWARE UPDATES & RELEASES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("v\(UpdateManager.shared.currentVersion)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text("Chibiori checks GitHub Releases for new updates automatically. You can install new releases and relaunch with 1 click without rebuilding manually.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Button {
                    UpdateManager.shared.checkForUpdates(manual: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Check for Updates...")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassPill(tint: .cyan, isSelected: false)
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://github.com/Ghostkwebb/Chibiori/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("View on GitHub")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassPill(tint: .secondary, isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
