import SwiftUI
import AppKit

public struct UpdateModalView: View {
    @Environment(\.dismiss) private var dismiss
    private var updateManager = UpdateManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 20) {
                // Header Icon
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.35), Color.purple.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)

                        Image(systemName: headerIconName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(headerIconColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(headerTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("Current: v\(updateManager.currentVersion)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Content based on update state
                switch updateManager.state {
                case .checking:
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Checking GitHub for the latest releases...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                case .upToDate:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.green)
                        Text("Chibiori is Up to Date")
                            .font(.system(size: 15, weight: .bold))
                        Text("You are already running the latest version (v\(updateManager.currentVersion)).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                case .available(let release):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("New Version Available:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(release.tag_name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.15))
                                .clipShape(Capsule())

                            Spacer()

                            if let published = release.published_at?.prefix(10) {
                                Text(String(published))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // Changelog Box
                        if let notes = release.body, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("RELEASE NOTES")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)

                                ScrollView {
                                    Text(notes)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(height: 110)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                    }

                case .downloading:
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Downloading update from GitHub...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("The app will automatically extract and relaunch once finished.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                case .extracting, .readyToRelaunch:
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Installing update and relaunching...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                case .error(let errorMsg):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Update Check Failed")
                            .font(.system(size: 14, weight: .bold))
                        Text(errorMsg)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                case .idle:
                    EmptyView()
                }

                Divider()

                // Actions Footer
                HStack {
                    if case .error = updateManager.state {
                        Button("Open GitHub Releases") {
                            if let url = URL(string: "https://github.com/Ghostkwebb/Chibiori/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassPill(tint: .secondary, isSelected: false)
                    }

                    Spacer()

                    if case .available(let release) = updateManager.state {
                        Button("Later") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .glassPill(tint: .secondary, isSelected: false)

                        Button {
                            updateManager.downloadAndInstallUpdate(release: release)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Update & Relaunch")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .glassPill(tint: .cyan, isSelected: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 460)
        .glassCard(cornerRadius: 18)
    }

    private var headerIconName: String {
        switch updateManager.state {
        case .checking: return "arrow.clockwise"
        case .upToDate: return "checkmark.shield.fill"
        case .available: return "sparkles"
        case .downloading, .extracting, .readyToRelaunch: return "arrow.down.app.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "arrow.clockwise"
        }
    }

    private var headerIconColor: Color {
        switch updateManager.state {
        case .checking: return .cyan
        case .upToDate: return .green
        case .available: return .cyan
        case .downloading, .extracting, .readyToRelaunch: return .purple
        case .error: return .orange
        case .idle: return .cyan
        }
    }

    private var headerTitle: String {
        switch updateManager.state {
        case .checking: return "Checking for Updates..."
        case .upToDate: return "You're Up to Date"
        case .available: return "Update Available"
        case .downloading: return "Downloading Update..."
        case .extracting, .readyToRelaunch: return "Installing Update..."
        case .error: return "Update Error"
        case .idle: return "Software Update"
        }
    }
}
