import SwiftUI

struct CustomTitleEditorSheet: View {
    @Binding var tempTitle: String
    let onClear: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Custom Anime Title")
                .font(.system(size: 15, weight: .bold))

            Text("Enter a custom title to display for this anime across your library, or clear it to use the default title.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Custom Title (e.g. Lord of the Mysteries)", text: $tempTitle)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Clear Override", action: onClear)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)

                Button("Save Title", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 380)
    }
}
