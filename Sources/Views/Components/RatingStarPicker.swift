import SwiftUI

public struct RatingStarPicker: View {
    @Binding var rating: Int?
    @State private var hoveredRating: Int? = nil

    public init(rating: Binding<Int?>) {
        self._rating = rating
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { star in
                Image(systemName: starIconName(for: star))
                    .font(.system(size: 14))
                    .foregroundStyle(starColor(for: star))
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        hoveredRating = isHovered ? star : nil
                    }
                    .onTapGesture {
                        if rating == star {
                            rating = nil // toggle off
                        } else {
                            rating = star
                        }
                    }
            }

            if let current = rating {
                Text("\(current)/10")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                Button {
                    rating = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear rating")
            } else {
                Text("Unrated")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }

    private func starIconName(for star: Int) -> String {
        let activeValue = hoveredRating ?? rating ?? 0
        return star <= activeValue ? "star.fill" : "star"
    }

    private func starColor(for star: Int) -> Color {
        let activeValue = hoveredRating ?? rating ?? 0
        if star <= activeValue {
            return .yellow
        }
        return Color(nsColor: .quaternaryLabelColor)
    }
}
