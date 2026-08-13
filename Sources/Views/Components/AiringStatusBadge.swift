import SwiftUI

public struct AiringStatusBadge: View {
    let status: AiringStatus?

    public init(status: AiringStatus?) {
        self.status = status
    }

    public var body: some View {
        if let status {
            HStack(spacing: 4) {
                Circle()
                    .fill(status.badgeColor)
                    .frame(width: 6, height: 6)
                Text(status.displayName)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.badgeColor.opacity(0.15))
            .foregroundStyle(status.badgeColor)
            .clipShape(Capsule())
        }
    }
}
