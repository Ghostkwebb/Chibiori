import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class CloudSyncService {
    public static let shared = CloudSyncService()

    public var isCloudSyncEnabled: Bool = true
    public var lastCloudSyncDate: Date? = nil
    public var syncStatusText: String = "iCloud Sync Ready"
    public var isSyncing: Bool = false

    private let fileManager = FileManager.default
    private let cloudDocsFolderName = "Chibiori"
    private let syncFileName = "Chibiori_CloudSync.json"

    private init() {
        checkCloudDriveAvailability()
    }

    /// URL for the iCloud Drive Documents directory for Chibiori
    private var iCloudVaultDirectoryURL: URL? {
        if let url = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").appendingPathComponent(cloudDocsFolderName) {
            return url
        }
        // Fallback to standard local Mobile Documents path
        let home = fileManager.homeDirectoryForCurrentUser
        let localMobileDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/\(cloudDocsFolderName)")
        return localMobileDocs
    }

    private var iCloudSyncFileURL: URL? {
        iCloudVaultDirectoryURL?.appendingPathComponent(syncFileName)
    }

    /// Checks if iCloud Drive is accessible on this Mac
    public func checkCloudDriveAvailability() {
        if let dir = iCloudVaultDirectoryURL {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            if let syncFile = iCloudSyncFileURL, fileManager.fileExists(atPath: syncFile.path) {
                if let attrs = try? fileManager.attributesOfItem(atPath: syncFile.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    self.lastCloudSyncDate = modDate
                    self.syncStatusText = "iCloud Vault Synced"
                }
            }
        }
    }

    /// Automatically backs up all current tracked anime to the iCloud Drive Vault
    public func performAutoCloudBackup(from animes: [TrackedAnime]) {
        guard isCloudSyncEnabled, !animes.isEmpty else { return }

        Task.detached(priority: .utility) {
            do {
                let data = try BackupService.shared.generateExportData(from: animes)

                await MainActor.run {
                    guard let dir = self.iCloudVaultDirectoryURL,
                          let fileURL = self.iCloudSyncFileURL else { return }

                    if !self.fileManager.fileExists(atPath: dir.path) {
                        try? self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                    }

                    do {
                        try data.write(to: fileURL, options: .atomic)
                        self.lastCloudSyncDate = Date()
                        self.syncStatusText = "iCloud Vault Updated"
                    } catch {
                        self.syncStatusText = "Local Sync Ready"
                    }
                }
            } catch {
                // Background sync failure ignored gracefully
            }
        }
    }

    /// Automatically restores library from iCloud Drive if the local library is empty
    public func autoRestoreIfLibraryEmpty(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TrackedAnime>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return false }

        guard let fileURL = iCloudSyncFileURL,
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return false
        }

        do {
            let summary = try BackupService.shared.importBackup(data: data, context: context)
            if summary.insertedCount > 0 {
                self.syncStatusText = "Auto-Restored \(summary.insertedCount) anime from iCloud"
                self.lastCloudSyncDate = Date()
                return true
            }
        } catch {
            return false
        }

        return false
    }
}
