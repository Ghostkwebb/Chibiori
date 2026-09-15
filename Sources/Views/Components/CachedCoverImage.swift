import SwiftUI
import AppKit

public struct CachedCoverImage: View {
    let malID: Int
    let remoteURLString: String
    let localFilename: String?
    var cornerRadius: CGFloat = 8
    var shadowRadius: CGFloat = 0

    @State private var asyncImage: NSImage?

    public init(
        malID: Int,
        remoteURLString: String,
        localFilename: String? = nil,
        cornerRadius: CGFloat = 8,
        shadowRadius: CGFloat = 0
    ) {
        self.malID = malID
        self.remoteURLString = remoteURLString
        self.localFilename = localFilename
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }

    private var currentDisplayImage: NSImage? {
        if let memoryImage = CoverImageManager.shared.synchronousImage(malID: malID, existingFilename: localFilename) {
            return memoryImage
        }
        return asyncImage
    }

    public var body: some View {
        Group {
            let imageContent = ZStack {
                if let img = currentDisplayImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(225 / 318, contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if shadowRadius > 0 {
                imageContent
                    .shadow(color: .black.opacity(0.18), radius: shadowRadius, x: 0, y: 2)
            } else {
                imageContent
            }
        }
        .task(id: "\(malID)_\(remoteURLString)") {
            if CoverImageManager.shared.synchronousImage(malID: malID, existingFilename: localFilename) != nil {
                return
            }
            let (fetchedImage, _) = await CoverImageManager.shared.loadImage(
                malID: malID,
                remoteURLString: remoteURLString,
                existingFilename: localFilename
            )
            if let fetchedImage {
                self.asyncImage = fetchedImage
            }
        }
    }
}
