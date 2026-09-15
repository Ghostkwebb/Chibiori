import AppKit
import SwiftUI

@MainActor
public final class StatusMenuPresenter: NSObject {
    public static let shared = StatusMenuPresenter()

    private var currentCallback: ((WatchStatus) -> Void)?
    private var removeCallback: (() -> Void)?

    public func presentMenu(
        currentStatus: WatchStatus?,
        headerTitle: String = "MOVE TO STATUS",
        includeRemoveAction: Bool = false,
        onRemove: (() -> Void)? = nil,
        onSelect: @escaping (WatchStatus) -> Void
    ) {
        self.currentCallback = onSelect
        self.removeCallback = onRemove

        let menu = NSMenu(title: "Status Menu")
        menu.autoenablesItems = false

        // Section header
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Status items with color-coded SF Symbol icons
        for status in WatchStatus.allCases {
            let item = NSMenuItem()
            item.title = status.displayName
            item.target = self
            item.representedObject = status
            item.action = #selector(menuItemClicked(_:))
            item.keyEquivalent = ""

            let attrTitle = NSMutableAttributedString()
            attrTitle.append(NSAttributedString(attachment: status.coloredIconAttachment(size: 14)))
            attrTitle.append(NSAttributedString(string: "  "))

            let textAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            attrTitle.append(NSAttributedString(string: status.displayName, attributes: textAttr))

            item.attributedTitle = attrTitle
            item.isEnabled = true
            if currentStatus == status {
                item.state = .on
            }
            menu.addItem(item)
        }

        // Optional Remove action (for franchise hub, etc.)
        if includeRemoveAction, onRemove != nil {
            menu.addItem(NSMenuItem.separator())
            let removeItem = NSMenuItem()
            removeItem.title = "Remove from Library"
            removeItem.target = self
            removeItem.action = #selector(removeItemClicked(_:))
            removeItem.keyEquivalent = ""

            let removeAttrTitle = NSMutableAttributedString()
            removeAttrTitle.append(NSAttributedString(attachment: makeTrashAttachment(size: 14)))
            removeAttrTitle.append(NSAttributedString(string: "  "))

            let textAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 13)
            ]
            removeAttrTitle.append(NSAttributedString(string: "Remove from Library", attributes: textAttr))

            removeItem.attributedTitle = removeAttrTitle
            removeItem.isEnabled = true
            menu.addItem(removeItem)
        }

        // Pop up directly at the mouse cursor position in screen coordinates
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let status = sender.representedObject as? WatchStatus else { return }
        currentCallback?(status)
    }

    @objc private func removeItemClicked(_ sender: NSMenuItem) {
        removeCallback?()
    }

    private func makeTrashAttachment(size: CGFloat = 14) -> NSTextAttachment {
        let iconSize = NSSize(width: size, height: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size * 2),
            pixelsHigh: Int(size * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSTextAttachment()
        }
        rep.size = iconSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let config = NSImage.SymbolConfiguration(pointSize: size - 2, weight: .bold)
            .applying(.init(paletteColors: [.systemRed]))
        if let sym = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Remove")?.withSymbolConfiguration(config) {
            let ox = (iconSize.width - sym.size.width) / 2
            let oy = (iconSize.height - sym.size.height) / 2
            sym.draw(in: NSRect(x: ox, y: oy, width: sym.size.width, height: sym.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: iconSize)
        img.addRepresentation(rep)
        img.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = img
        attachment.bounds = CGRect(x: 0, y: -2.5, width: iconSize.width, height: iconSize.height)
        return attachment
    }
}
