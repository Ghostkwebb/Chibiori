import SwiftUI
import AppKit

public struct SmoothScrollModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
    }
}

extension View {
    public func smooth120HzScroll() -> some View {
        self.modifier(SmoothScrollModifier())
    }
}

