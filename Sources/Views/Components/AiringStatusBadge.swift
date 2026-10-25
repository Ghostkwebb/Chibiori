import SwiftUI

public struct AiringStatusBadge: View {
    let status: AiringStatus?

    public init(status: AiringStatus?) {
        self.status = status
    }

    public var body: some View {
        if let status {
            HStack(spacing: 4.5) {
                Circle()
                    .fill(status.dotColor)
                    .frame(width: 5.5, height: 5.5)

                Text(status.shortDisplayName)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.black.opacity(0.78))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(status.dotColor.opacity(0.45), lineWidth: 0.8)
            )
        }
    }
}
