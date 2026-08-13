import Foundation
import AppKit
import ImageIO

public final class MemoryImageCache: @unchecked Sendable {
    public static let shared = MemoryImageCache()
    private let cache = NSCache<NSString, NSImage>()

    public init() {
        cache.countLimit = 300
        cache.totalCostLimit = 150 * 1024 * 1024 // 150MB RAM cache
    }

    public func image(for malID: Int) -> NSImage? {
        cache.object(forKey: "mal_\(malID)" as NSString)
    }

    public func setImage(_ image: NSImage, for malID: Int, cost: Int = 0) {
        cache.setObject(image, forKey: "mal_\(malID)" as NSString, cost: cost)
    }

    public func clear() {
        cache.removeAllObjects()
    }
}

public actor CoverImageManager {
    public static let shared = CoverImageManager()

    private let fileManager = FileManager.default
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private var coversDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let chibioriDir = appSupport.appendingPathComponent("Chibiori", isDirectory: true)
        let coversDir = chibioriDir.appendingPathComponent("Covers", isDirectory: true)

        if !fileManager.fileExists(atPath: coversDir.path) {
            try? fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
        }
        return coversDir
    }

    public init() {}

    /// Fast synchronous memory-cache check helper
    public nonisolated func cachedImage(for malID: Int) -> NSImage? {
        MemoryImageCache.shared.image(for: malID)
    }

    /// Returns a local file URL for a given filename or relative path
    public nonisolated func localFileURL(for filename: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Chibiori/Covers/\(filename)")
    }

    /// High performance downsampling to keep RAM and GPU texture uploads minimal
    private nonisolated func downsample(data: Data, maxPixelSize: CGFloat = 450) -> NSImage? {
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
        guard !remoteURLString.isEmpty else { return (nil, nil) }

        // 1. Instant check memory cache
        if let cachedImage = MemoryImageCache.shared.image(for: malID) {
            let filename = existingFilename ?? "cover_\(malID).jpg"
            return (cachedImage, filename)
        }

        // 2. Check disk cache
        let targetFilename = existingFilename ?? "cover_\(malID).jpg"
        let diskURL = coversDirectoryURL.appendingPathComponent(targetFilename)

        if fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL) {
            let diskImage = downsample(data: data) ?? NSImage(data: data)
            if let diskImage {
                MemoryImageCache.shared.setImage(diskImage, for: malID, cost: data.count)
                return (diskImage, targetFilename)
            }
        }

        // 3. Prevent duplicate in-flight network requests
        if let ongoing = inFlightTasks[remoteURLString] {
            let image = await ongoing.value
            return (image, targetFilename)
        }

        let downloadTask = Task<NSImage?, Never> {
            guard let url = URL(string: remoteURLString) else { return nil }
            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15.0)
                request.setValue("Chibiori-macOS/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return nil
                }

                // Save to disk in background
                try? data.write(to: diskURL, options: .atomic)

                // Downsample for display
                let finalImage = self.downsample(data: data) ?? NSImage(data: data)
                if let finalImage {
                    MemoryImageCache.shared.setImage(finalImage, for: malID, cost: data.count)
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

    /// Clear memory and disk covers cache
    public func clearCache() {
        MemoryImageCache.shared.clear()
        try? fileManager.removeItem(at: coversDirectoryURL)
    }
}
