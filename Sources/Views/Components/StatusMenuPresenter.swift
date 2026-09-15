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

        // Status items with colored indicators
        for status in WatchStatus.allCases {
            let item = NSMenuItem(
                title: status.displayName,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = status
            item.image = status.coloredIndicatorDot
            item.image?.isTemplate = false
            item.isEnabled = true
            if currentStatus == status {
                item.state = .on
            }
            menu.addItem(item)
        }

        // Optional Remove action (for franchise hub, etc.)
        if includeRemoveAction, onRemove != nil {
            menu.addItem(NSMenuItem.separator())
            let removeItem = NSMenuItem(
                title: "Remove from Library",
                action: #selector(removeItemClicked(_:)),
                keyEquivalent: ""
            )
            removeItem.target = self
            let trashConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                .applying(.init(paletteColors: [.systemRed]))
            if let trashImg = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove")?.withSymbolConfiguration(trashConfig) {
                trashImg.isTemplate = false
                removeItem.image = trashImg
            }
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
}
