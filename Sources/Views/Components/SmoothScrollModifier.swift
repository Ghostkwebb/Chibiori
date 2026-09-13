import SwiftUI
import AppKit

public struct SmoothScrollModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(SmoothScrollIntrospector())
    }
}

private struct SmoothScrollIntrospector: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                configureScrollView(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                configureScrollView(scrollView)
            }
        }
    }

    private func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false

        // Native macOS momentum physics & axis locking
        scrollView.usesPredominantAxisScrolling = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none

        // Seamless overlay scrollers
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }
}

extension View {
    public func smooth120HzScroll() -> some View {
        self.modifier(SmoothScrollModifier())
    }
}
