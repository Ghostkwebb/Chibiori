import Foundation
import AppKit
import Observation

public struct GitHubReleaseAsset: Codable, Sendable, Equatable {
    public let name: String
    public let browser_download_url: String
    public let size: Int
}

public struct GitHubRelease: Codable, Identifiable, Sendable, Equatable {
    public var id: String { tag_name }
    public let tag_name: String
    public let name: String?
    public let body: String?
    public let published_at: String?
    public let html_url: String
    public let assets: [GitHubReleaseAsset]

    public var zipAsset: GitHubReleaseAsset? {
        assets.first { $0.name.hasSuffix(".zip") }
    }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease)
    case downloading(progress: Double)
    case extracting
    case readyToRelaunch
    case error(String)
}

@Observable
@MainActor
public final class UpdateManager: NSObject {
    public static let shared = UpdateManager()

    public var state: UpdateState = .idle
    public var showUpdateSheet: Bool = false
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private let githubRepo = "Ghostkwebb/Chibiori"
    private var downloadTask: URLSessionDownloadTask?
    private var activeContinuation: CheckedContinuation<URL, Error>?

    private override init() {
        super.init()
    }

    /// Compares two semver strings like "v1.0.1" and "1.0.0"
    public static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocal = local.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)

        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let localParts = cleanLocal.split(separator: ".").compactMap { Int($0) }

        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    /// Queries GitHub API for the latest release
    public func checkForUpdates(manual: Bool = false) {
        guard state != .checking && !isDownloading else { return }
        state = .checking

        Task {
            do {
                guard let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else {
                    throw NSError(domain: "Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub URL"])
                }

                var request = URLRequest(url: url)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("Chibiori-macOS-Updater/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                }

                if httpResponse.statusCode == 404 {
                    // No releases published yet
                    self.state = .upToDate
                    if manual { self.showUpdateSheet = true }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Update", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API returned status \(httpResponse.statusCode)"])
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                if Self.isVersion(release.tag_name, newerThan: self.currentVersion) {
                    self.state = .available(release)
                    self.showUpdateSheet = true
                } else {
                    self.state = .upToDate
                    if manual { self.showUpdateSheet = true }
                }
            } catch {
                self.state = .error(error.localizedDescription)
                if manual { self.showUpdateSheet = true }
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    /// Downloads, unzips, replaces the app bundle, and relaunches
    public func downloadAndInstallUpdate(release: GitHubRelease) {
        guard let asset = release.zipAsset,
              let downloadURL = URL(string: asset.browser_download_url) else {
            // Fallback: open release page in browser if no zip asset is attached
            if let webURL = URL(string: release.html_url) {
                NSWorkspace.shared.open(webURL)
            }
            return
        }

        self.state = .downloading(progress: 0.0)

        Task.detached(priority: .userInitiated) {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Chibiori_Update_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let zipDest = tempDir.appendingPathComponent("Chibiori.zip")

                // Download zip file
                var request = URLRequest(url: downloadURL)
                request.setValue("Chibiori-macOS-Updater/1.0", forHTTPHeaderField: "User-Agent")

                let (tempDownloadedURL, response) = try await URLSession.shared.download(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to download update bundle"])
                }

                try FileManager.default.moveItem(at: tempDownloadedURL, to: zipDest)

                await MainActor.run {
                    self.state = .extracting
                }

                // Unzip using /usr/bin/ditto (preserves macOS app metadata and symlinks)
                let extractProcess = Process()
                extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                extractProcess.arguments = ["-xk", zipDest.path, tempDir.path]
                try extractProcess.run()
                extractProcess.waitUntilExit()

                guard extractProcess.terminationStatus == 0 else {
                    throw NSError(domain: "Update", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update package"])
                }

                let newAppURL = tempDir.appendingPathComponent("Chibiori.app")
                guard FileManager.default.fileExists(atPath: newAppURL.path) else {
                    throw NSError(domain: "Update", code: 5, userInfo: [NSLocalizedDescriptionKey: "Extracted archive does not contain Chibiori.app"])
                }

                // Strip quarantine attribute
                let xattrProcess = Process()
                xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProcess.arguments = ["-dr", "com.apple.quarantine", newAppURL.path]
                try? xattrProcess.run()
                xattrProcess.waitUntilExit()

                // Target current running bundle path (or /Applications/Chibiori.app fallback)
                let targetAppURL: URL = Bundle.main.bundleURL.pathExtension == "app" ?
                    Bundle.main.bundleURL :
                    URL(fileURLWithPath: "/Applications/Chibiori.app")

                await MainActor.run {
                    self.state = .readyToRelaunch
                    self.executeRelaunchHelper(newAppURL: newAppURL, targetAppURL: targetAppURL)
                }
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Spawns a detached background shell helper to replace the running bundle and launch the new version
    private func executeRelaunchHelper(newAppURL: URL, targetAppURL: URL) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let scriptContent = """
        #!/bin/bash
        # Wait for current app instance to terminate
        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 0.1
        done

        # Replace old app bundle with new one
        rm -rf "\(targetAppURL.path)"
        mv "\(newAppURL.path)" "\(targetAppURL.path)"

        # Launch the new app
        open "\(targetAppURL.path)"
        """

        let helperScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("chibiori_relaunch.sh")
        try? scriptContent.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", helperScriptURL.path]
        try? chmodProcess.run()
        chmodProcess.waitUntilExit()

        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        launchProcess.arguments = [helperScriptURL.path]
        try? launchProcess.run()

        // Terminate current running instance immediately
        NSApplication.shared.terminate(nil)
    }
}
