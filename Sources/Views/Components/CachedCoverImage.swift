import SwiftUI
import AppKit

public struct CachedCoverImage: View {
    let malID: Int
    let remoteURLString: String
    let localFilename: String?
    var cornerRadius: CGFloat = 8
    var shadowRadius: CGFloat = 4

    @State private var asyncImage: NSImage?
    @State private var isLoading = false

    public init(
        malID: Int,
        remoteURLString: String,
        localFilename: String? = nil,
        cornerRadius: CGFloat = 8,
        shadowRadius: CGFloat = 4
    ) {
        self.malID = malID
        self.remoteURLString = remoteURLString
        self.localFilename = localFilename
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }

    private var currentDisplayImage: NSImage? {
        if let memoryImage = CoverImageManager.shared.cachedImage(for: malID) {
            return memoryImage
        }
        return asyncImage
    }

    public var body: some View {
        ZStack {
            if let img = currentDisplayImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(225 / 318, contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "film")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("No Poster")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: shadowRadius, x: 0, y: 2)
        .task(id: "\(malID)_\(remoteURLString)") {
            // If already cached synchronously in RAM, do not perform async load or state mutation
            if CoverImageManager.shared.cachedImage(for: malID) != nil {
                return
            }
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        let (fetchedImage, _) = await CoverImageManager.shared.loadImage(
            malID: malID,
            remoteURLString: remoteURLString,
            existingFilename: localFilename
        )
        if let fetchedImage {
            self.asyncImage = fetchedImage
        }
        self.isLoading = false
    }
}
