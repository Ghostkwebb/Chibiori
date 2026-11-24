import Foundation
import AppKit
import ImageIO

/// Thread-safe in-memory cover image cache with decoded bitmap cost accounting.
public final class MemoryImageCache: @unchecked Sendable {
    public static let shared = MemoryImageCache()
    private let cache = NSCache<NSString, NSImage>()

    public init(countLimit: Int = 600, totalCostLimit: Int = 256 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    public func image(for malID: Int) -> NSImage? {
        cache.object(forKey: "mal_\(malID)" as NSString)
    }

    public func setImage(_ image: NSImage, for malID: Int, cost: Int? = nil) {
        let computedCost = cost ?? Self.decodedBitmapCost(for: image)
        cache.setObject(image, forKey: "mal_\(malID)" as NSString, cost: computedCost)
    }

    public func clear() {
        cache.removeAllObjects()
    }

    public static func decodedBitmapCost(for image: NSImage) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }
        return max(1, Int(image.size.width * image.size.height * 4))
    }
}

/// Manages cover downloads, disk persistence, downsampling, and bounded parallel memory pre-warming.
public actor CoverImageManager {
    public static let shared = CoverImageManager()

    private let fileManager = FileManager.default
    private let coversDirectoryURL: URL
    private let session: URLSession
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    public init(cacheDirectory: URL? = nil, session: URLSession = .shared) {
        if let cacheDirectory {
            self.coversDirectoryURL = cacheDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.coversDirectoryURL = appSupport.appendingPathComponent("Chibiori/Covers", isDirectory: true)
        }
        self.session = session
        if !FileManager.default.fileExists(atPath: coversDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private nonisolated static var defaultCoversDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Chibiori/Covers", isDirectory: true)
    }

    /// Fast synchronous memory-cache check helper (zero main-thread disk I/O).
    public nonisolated func cachedImage(for malID: Int) -> NSImage? {
        MemoryImageCache.shared.image(for: malID)
    }

    /// Returns a local file URL for a given filename or relative path.
    public nonisolated func localFileURL(for filename: String) -> URL {
        coversDirectoryURL.appendingPathComponent(filename)
    }

    /// Instant in-memory check for UI body evaluation. Never performs synchronous disk I/O on main thread.
    public nonisolated func synchronousImage(malID: Int, existingFilename: String? = nil) -> NSImage? {
        MemoryImageCache.shared.image(for: malID)
    }

    /// Background disk loader with downsampling, safe to run concurrently across any thread.
    public nonisolated func loadDiskImage(malID: Int, existingFilename: String? = nil) -> NSImage? {
        if let memoryImage = MemoryImageCache.shared.image(for: malID) {
            return memoryImage
        }
        let targetFilename = (existingFilename != nil && !existingFilename!.isEmpty) ? existingFilename! : "cover_\(malID).jpg"
        let diskURL = localFileURL(for: targetFilename)
        guard FileManager.default.fileExists(atPath: diskURL.path),
              let data = try? Data(contentsOf: diskURL, options: .mappedIfSafe) else {
            return nil
        }
        let img = Self.downsample(data: data) ?? NSImage(data: data)
        if let img {
            MemoryImageCache.shared.setImage(img, for: malID)
        }
        return img
    }

    /// High-performance downsampling to keep RAM and GPU texture uploads minimal.
    public nonisolated static func downsample(data: Data, maxPixelSize: CGFloat = 450) -> NSImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return NSImage(data: data)
        }

        let maxDimension = max(maxPixelSize, 100)
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let downsampledCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return NSImage(data: data)
        }

        let size = NSSize(width: downsampledCGImage.width, height: downsampledCGImage.height)
        return NSImage(cgImage: downsampledCGImage, size: size)
    }

    /// Loads an image for an anime given its malID, remote URL, and optional cached local filename.
    public func loadImage(malID: Int, remoteURLString: String, existingFilename: String? = nil) async -> (image: NSImage?, localFilename: String?) {
        if let cachedImage = MemoryImageCache.shared.image(for: malID) {
            let filename = existingFilename ?? "cover_\(malID).jpg"
            return (cachedImage, filename)
        }

        let targetFilename = (existingFilename != nil && !existingFilename!.isEmpty) ? existingFilename! : "cover_\(malID).jpg"
        let diskImage = await Task.detached(priority: .userInitiated) {
            self.loadDiskImage(malID: malID, existingFilename: targetFilename)
        }.value

        if let diskImage {
            return (diskImage, targetFilename)
        }

        guard !remoteURLString.isEmpty else { return (nil, nil) }

        if let ongoing = inFlightTasks[remoteURLString] {
            let image = await ongoing.value
            return (image, targetFilename)
        }

        let diskURL = coversDirectoryURL.appendingPathComponent(targetFilename)
        let urlSession = session
        let downloadTask = Task<NSImage?, Never> {
            guard let url = URL(string: remoteURLString) else { return nil }
            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15.0)
                request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return nil
                }

                try? data.write(to: diskURL, options: .atomic)

                let finalImage = Self.downsample(data: data) ?? NSImage(data: data)
                if let finalImage {
                    MemoryImageCache.shared.setImage(finalImage, for: malID)
                }
                return finalImage
            } catch {
                return nil
            }
        }

        inFlightTasks[remoteURLString] = downloadTask
        let resultImage = await downloadTask.value
        inFlightTasks.removeValue(forKey: remoteURLString)

        return (resultImage, targetFilename)
    }

    /// Pre-warms up to 40 uncached disk covers into RAM using a sliding window of at most 4 concurrent tasks.
    public nonisolated func prefetchCovers(items: [(malID: Int, url: String, filename: String?)]) {
        let filtered = Array(
            items
                .filter { MemoryImageCache.shared.image(for: $0.malID) == nil }
                .prefix(40)
        )
        guard !filtered.isEmpty else { return }

        Task.detached(priority: .utility) {
            let maxConcurrent = 4
            var nextIndex = 0
            await withTaskGroup(of: Void.self) { group in
                let initial = min(maxConcurrent, filtered.count)
                while nextIndex < initial {
                    let item = filtered[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        if Task.isCancelled { return }
                        _ = CoverImageManager.shared.loadDiskImage(malID: item.malID, existingFilename: item.filename)
                    }
                }

                for await _ in group {
                    if Task.isCancelled { break }
                    if nextIndex < filtered.count {
                        let item = filtered[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            if Task.isCancelled { return }
                            _ = CoverImageManager.shared.loadDiskImage(malID: item.malID, existingFilename: item.filename)
                        }
                    }
                }
            }
        }
    }

    /// Clears memory and disk cover caches and recreates the covers directory.
    public func clearCache() {
        MemoryImageCache.shared.clear()
        try? fileManager.removeItem(at: coversDirectoryURL)
        try? fileManager.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
    }
}
