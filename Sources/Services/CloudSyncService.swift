import Foundation
import AppKit
import SwiftData
import Observation

/// Syncs the Chibiori library to iCloud Drive as a JSON file.
///
/// Strategy: Since the app is not sandboxed and runs as the current user,
/// we write directly to ~/Library/Mobile Documents/com~apple~CloudDocs/Chibiori/
/// which is the backing store for iCloud Drive. The macOS `bird` daemon automatically
/// picks up changes there and syncs them — no developer account or special entitlements needed.
///
/// On a fresh Mac (after a wipe), the file may exist on Apple's servers but not yet been
/// downloaded. We use NSMetadataQuery to detect that case and trigger a download before
/// attempting to restore.
@Observable
@MainActor
public final class CloudSyncService: NSObject {
    public static let shared = CloudSyncService()

    // MARK: - Published State

    public var isCloudSyncEnabled: Bool = true
    public var lastCloudSyncDate: Date? = nil
    public var syncStatusText: String = "iCloud Drive Ready"
    public var isSyncing: Bool = false

    // MARK: - Private

    private let fileManager = FileManager.default
    private let syncFileName = "Chibiori_CloudSync.json"
    private let folderName = "Chibiori"

    /// NSMetadataQuery used to detect when the sync file finishes downloading on a fresh Mac.
    private var metadataQuery: NSMetadataQuery?
    private var pendingRestoreContext: ModelContext?

    private override init() {
        super.init()
        refreshStatusFromDisk()
    }

    // MARK: - iCloud Drive Path Resolution

    /// Returns the Chibiori folder inside iCloud Drive root.
    ///
    /// ~/Library/Mobile Documents/com~apple~CloudDocs/Chibiori/
    ///
    /// This is the user's iCloud Drive, accessible without any app entitlements when
    /// the app is not sandboxed. The OS syncs everything written here automatically.
    private var iCloudDriveFolderURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private var syncFileURL: URL {
        iCloudDriveFolderURL.appendingPathComponent(syncFileName)
    }

    // MARK: - Status

    /// Reads the modification date of the existing sync file (if any) to populate status on launch.
    private func refreshStatusFromDisk() {
        let url = syncFileURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            self.lastCloudSyncDate = modDate
            self.syncStatusText = "iCloud Drive Synced"
        }
    }

    /// Returns true if iCloud Drive is accessible and writable.
    public var isICloudDriveAvailable: Bool {
        let parent = iCloudDriveFolderURL.deletingLastPathComponent()
        return fileManager.fileExists(atPath: parent.path)
    }

    // MARK: - Backup / Write

    /// Serializes the current anime list to JSON and writes it atomically to iCloud Drive
    /// using NSFileCoordinator to prevent corruption from concurrent access.
    public func performAutoCloudBackup(from animes: [TrackedAnime]) {
        guard isCloudSyncEnabled, !animes.isEmpty else { return }
        guard !isSyncing else { return }

        isSyncing = true

        // Capture values for background use
        let folderURL = iCloudDriveFolderURL
        let fileURL = syncFileURL

        Task.detached(priority: .utility) {
            do {
                let data = try BackupService.shared.generateExportData(from: animes)

                // Ensure the Chibiori folder exists inside iCloud Drive
                if !FileManager.default.fileExists(atPath: folderURL.path) {
                    try FileManager.default.createDirectory(
                        at: folderURL,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }

                // Write via NSFileCoordinator for safe concurrent access
                var writeSucceeded = false
                var coordinatorError: NSError?
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { resolvedURL in
                    do {
                        try data.write(to: resolvedURL, options: .atomic)
                        writeSucceeded = true
                    } catch {
                        writeSucceeded = false
                    }
                }
                let success = writeSucceeded && coordinatorError == nil

                await MainActor.run {
                    if success {
                        self.lastCloudSyncDate = Date()
                        self.syncStatusText = "iCloud Drive Updated"
                    } else {
                        self.syncStatusText = "Sync Write Failed"
                    }
                    self.isSyncing = false
                }
            } catch {
                await MainActor.run {
                    self.syncStatusText = "Sync Encode Failed"
                    self.isSyncing = false
                }
            }
        }
    }

    // MARK: - Restore on Fresh Mac

    /// Call on app launch. If the local library is empty, checks for a sync file in iCloud Drive.
    ///
    /// Two cases:
    /// 1. File already downloaded locally → restore immediately.
    /// 2. File exists on Apple's servers but not yet downloaded → start NSMetadataQuery to watch
    ///    for download completion, then restore when it arrives.
    @discardableResult
    public func autoRestoreIfLibraryEmpty(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TrackedAnime>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return false }

        let fileURL = syncFileURL

        // Case 1: File is already on disk
        if fileManager.fileExists(atPath: fileURL.path) {
            return attemptRestoreFromDisk(context: context)
        }

        // Case 2: File may be in iCloud but not yet downloaded — query for it
        if isICloudDriveAvailable {
            startMetadataQueryForRestore(context: context)
            syncStatusText = "Waiting for iCloud Download..."
        }

        return false
    }

    // MARK: - Immediate Disk Restore

    @discardableResult
    private func attemptRestoreFromDisk(context: ModelContext) -> Bool {
        let fileURL = syncFileURL

        // If the file is in the cloud but evicted, trigger download first
        let values = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
            try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
            startMetadataQueryForRestore(context: context)
            syncStatusText = "Downloading from iCloud..."
            return false
        }

        guard let data = try? Data(contentsOf: fileURL) else { return false }

        do {
            let summary = try BackupService.shared.importBackup(data: data, context: context)
            if summary.insertedCount > 0 {
                syncStatusText = "Restored \(summary.insertedCount) anime from iCloud Drive"
                lastCloudSyncDate = Date()
                return true
            }
        } catch {
            syncStatusText = "Restore Failed"
        }

        return false
    }

    // MARK: - NSMetadataQuery (iCloud Download Watcher)

    /// Starts a metadata query that watches for the sync file to become available in iCloud Drive.
    /// Once it downloads, the query fires and we restore automatically.
    private func startMetadataQueryForRestore(context: ModelContext) {
        guard metadataQuery == nil else { return }

        pendingRestoreContext = context

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@",
                                      NSMetadataItemFSNameKey,
                                      syncFileName)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        self.metadataQuery = query
    }

    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        guard let query = metadataQuery else { return }
        query.disableUpdates()

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // File is now downloaded — restore
                query.stop()
                metadataQuery = nil
                NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
                NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

                if let context = pendingRestoreContext {
                    pendingRestoreContext = nil
                    let restored = attemptRestoreFromDisk(context: context)
                    if !restored {
                        syncStatusText = "iCloud Drive Ready"
                    }
                }
                return
            } else {
                // File exists but not yet downloaded — trigger download
                if let urlValue = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    try? fileManager.startDownloadingUbiquitousItem(at: urlValue)
                    syncStatusText = "Downloading from iCloud..."
                }
            }
        }

        query.enableUpdates()
    }

    // MARK: - Manual Sync & Utilities

    /// Opens the Chibiori sync folder in Finder so the user can see where the file lives.
    public func revealInFinder() {
        let url = iCloudDriveFolderURL
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }
}
