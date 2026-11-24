import SwiftUI

struct DubbedLanguageEditorSheet: View {
    let anime: TrackedAnime
    @Binding var customLanguageInput: String
    let onToggleLanguage: (DubbedLanguage) -> Void
    let onAddCustomLanguage: (String) -> Void
    let onAutoDetect: () async -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Manage Dubbed Languages")
                .font(.system(size: 15, weight: .bold))

            Text("Select the audio and dub tracks available for this anime, or add custom regional languages.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(DubbedLanguage.standardCatalog) { standardLang in
                        let isIncluded = anime.dubbedLanguages.contains { DubbedLanguage.resolve(from: $0).code == standardLang.code }
                            || (standardLang.code == "JP" && anime.dubbedLanguages.isEmpty)
                        Button {
                            onToggleLanguage(standardLang)
                        } label: {
                            HStack(spacing: 4) {
                                if let flag = standardLang.flag {
                                    Text(flag)
                                }
                                Text(standardLang.name)
                                if isIncluded {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .font(.system(size: 11, weight: isIncluded ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isIncluded ? Color.purple.opacity(0.35) : Color.white.opacity(0.08))
                            .foregroundStyle(isIncluded ? Color.white : Color.secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isIncluded ? Color.purple.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 180)

            HStack(spacing: 8) {
                TextField("Add custom language (e.g. Tamil, Telugu, Catalan)...", text: $customLanguageInput)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    onAddCustomLanguage(customLanguageInput)
                    customLanguageInput = ""
                }
                .buttonStyle(.bordered)
                .disabled(customLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            HStack {
                Button("Auto-Detect Dubs") {
                    Task {
                        await onAutoDetect()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.purple)

                Spacer()

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 460, height: 390)
    }
}
