import SwiftUI
import AppKit

public struct AppLogoView: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 7

    public init(size: CGFloat = 28, cornerRadius: CGFloat = 7) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    private var logoImage: NSImage? {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        if let icnsURL = Bundle.main.url(forResource: "Chibiori_Logo", withExtension: "icns") ??
            Bundle.main.resourceURL?.appendingPathComponent("Chibiori_Logo.icns"),
           let image = NSImage(contentsOf: icnsURL) {
            return image
        }
        let icnsDesktop = "/Users/ghostkwebb/Desktop/Chibiori/Chibiori_Logo.icns"
        if FileManager.default.fileExists(atPath: icnsDesktop),
           let image = NSImage(contentsOfFile: icnsDesktop) {
            return image
        }
        return nil
    }

    public var body: some View {
        Group {
            if let nsImage = logoImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: size, height: size)
            }
        }
    }
}
