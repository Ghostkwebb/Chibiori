import SwiftUI

public struct RatingStarPicker: View {
    @Binding var rating: Int?
    @State private var hoveredRating: Int? = nil

    public init(rating: Binding<Int?>) {
        self._rating = rating
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(1...10, id: \.self) { star in
                Image(systemName: starIconName(for: star))
                    .font(.system(size: 13.5))
                    .foregroundStyle(starColor(for: star))
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        hoveredRating = isHovered ? star : nil
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if rating == star {
                                rating = nil // toggle off
                            } else {
                                rating = star
                            }
                        }
                    }
            }

            if rating != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        rating = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Clear rating")
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
