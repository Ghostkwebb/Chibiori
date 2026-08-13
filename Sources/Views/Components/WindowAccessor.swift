import SwiftUI
import AppKit

public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowObservingView: NSView {
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }

        // Optimize window performance for buttery smooth 120Hz Spaces & Mission Control swipes
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        window.animationBehavior = .default

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
            contentView.layer?.drawsAsynchronously = true
        }

        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
                guard let window, event.clickCount == 2 else {
                    return event
                }

                // Check if click is in the top bar / toolbar zone (top 54pt of window)
                let location = event.locationInWindow
                let windowHeight = window.frame.height
                let topBarThreshold = windowHeight - 54

                if location.y >= topBarThreshold {
                    // Check if the click target is a textfield or interactive control
                    let hitView = window.contentView?.hitTest(location)
                    if let hitView {
                        if hitView is NSTextField || hitView is NSControl || hitView is NSSearchField {
                            return event
                        }
                    }
                    // Double click on titlebar/top bar space -> Zoom / Maximize window
                    window.performZoom(nil)
                    return nil // Handled
                }

                return event
            }
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
