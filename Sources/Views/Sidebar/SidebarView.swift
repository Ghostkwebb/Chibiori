import SwiftUI
import SwiftData

@MainActor
public struct SidebarView: View {
    @Environment(NavigationState.self) private var navState
    @Binding var selection: SidebarSelection?
    @Query private var allAnime: [TrackedAnime]

    public init(selection: Binding<SidebarSelection?>) {
        self._selection = selection
    }

    private func count(for status: WatchStatus) -> Int {
        allAnime.filter { $0.watchStatus == status }.count
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Ambient Window Background
                AmbientGlowBackground()

                // Floating Detached Glassmorphic Sidebar Card
                VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Section 1: MY LIBRARY
                        sectionHeader("MY LIBRARY")

                        SidebarItemButton(
                            title: "All Anime",
                            systemImage: "square.grid.2x2.fill",
                            accentColor: .blue,
                            badgeCount: allAnime.isEmpty ? nil : allAnime.count,
                            isSelected: selection == .allAnime
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selection = .allAnime
                            }
                        }

                        ForEach(WatchStatus.allCases) { status in
                            let cnt = count(for: status)
                            SidebarItemButton(
                                title: status.displayName,
                                systemImage: status.systemImage,
                                accentColor: status.accentColor,
                                badgeCount: cnt > 0 ? cnt : nil,
                                isSelected: selection == .watchStatus(status)
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    selection = .watchStatus(status)
                                }
                            }
                        }

                        // Section 2: EXPLORE
                        sectionHeader("EXPLORE")
                            .padding(.top, 10)

                        SidebarItemButton(
                            title: "Search",
                            systemImage: "magnifyingglass",
                            accentColor: .teal,
                            badgeCount: nil,
                            isSelected: selection == .search
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selection = .search
                            }
                        }

                        SidebarItemButton(
                            title: "Weekly Calendar",
                            systemImage: "calendar.badge.clock",
                            accentColor: .indigo,
                            badgeCount: nil,
                            isSelected: selection == .weeklyCalendar
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selection = .weeklyCalendar
                            }
                        }

                        let sequelCount = SequelAlertService.shared.alerts.count
                        SidebarItemButton(
                            title: "Sequel Alerts",
                            systemImage: "bell.badge.fill",
                            accentColor: .purple,
                            badgeCount: sequelCount > 0 ? sequelCount : nil,
                            isSelected: selection == .sequelAlerts
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selection = .sequelAlerts
                            }
                        }

                        // Section 3: DATA
                        sectionHeader("DATA")
                            .padding(.top, 10)

                        SidebarItemButton(
                            title: "Import / Export Data",
                            systemImage: "arrow.triangle.2.circlepath.circle.fill",
                            accentColor: .orange,
                            badgeCount: nil,
                            isSelected: selection == .backup
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selection = .backup
                            }
                        }
                    }
                    .padding(10)
                }

                // Footer: Version & Check for Updates
                Divider()
                    .padding(.horizontal, 10)

                HStack(spacing: 8) {
                    Text("v\(UpdateManager.shared.currentVersion)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        UpdateManager.shared.checkForUpdates(manual: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Check Updates")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassPill(tint: .cyan, isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: 6)
            .padding(10)
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth >= 190 && newWidth <= 350 {
                    navState.sidebarWidth = newWidth
                }
            }
        }
    }
    .navigationSplitViewColumnWidth(min: 200, ideal: navState.sidebarWidth, max: 350)
}

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.secondary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct SidebarItemButton: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let badgeCount: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Active indicator line
                if isSelected {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 3, height: 16)
                        .shadow(color: accentColor.opacity(0.6), radius: 4, x: 0, y: 0)
                } else {
                    Spacer().frame(width: 3)
                }

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? accentColor : (isHovered ? accentColor.opacity(0.9) : accentColor.opacity(0.75)))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.primary : Color.primary.opacity(0.85)))

                Spacer()

                if let count = badgeCount {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? accentColor.opacity(0.5) : accentColor.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(accentColor.opacity(isSelected ? 0.6 : 0.25), lineWidth: 0.8)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(0.24),
                                        accentColor.opacity(0.08)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
                            )
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}
