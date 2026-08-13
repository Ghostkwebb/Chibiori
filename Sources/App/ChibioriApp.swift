import SwiftUI
import SwiftData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ChibioriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var navState = NavigationState()

    let container: ModelContainer

    init() {
        if CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("-t") {
            Task { @MainActor in
                let success = await SmokeTestRunner.runAllTests()
                exit(success ? 0 : 1)
            }
            RunLoop.main.run()
        }

        // Set macOS application dock icon from Chibiori_Logo.icns
        let icnsURL = Bundle.module.url(forResource: "Chibiori_Logo", withExtension: "icns") ??
            URL(fileURLWithPath: "/Users/ghostkwebb/Desktop/Chibiori/Chibiori_Logo.icns")
        if let iconImage = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        do {
            let schema = Schema([
                TrackedAnime.self
            ])
            // Configure SwiftData with Apple CloudKit synchronization
            let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Graceful fallback to local-only SQLite storage
            do {
                let schema = Schema([
                    TrackedAnime.self
                ])
                let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(navState)
                .modelContainer(container)
                .background(WindowAccessor())
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()

            CommandMenu("View") {
                Button("Poster Grid") {
                    navState.viewMode = .grid
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Compact Table") {
                    navState.viewMode = .table
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button(navState.showInspector ? "Hide Inspector" : "Show Inspector") {
                    navState.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }

            CommandMenu("Library") {
                Button("Search Anime...") {
                    navState.selectedSidebar = .search
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Weekly Calendar") {
                    navState.selectedSidebar = .weeklyCalendar
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Import / Export JSON...") {
                    navState.selectedSidebar = .backup
                }
            }
        }
    }
}

struct MainContentView: View {
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext
    @Query private var allAnime: [TrackedAnime]

    private var selectedAnime: TrackedAnime? {
        guard let id = navState.selectedAnimeID else { return nil }
        return modelContext.model(for: id) as? TrackedAnime
    }

    var body: some View {
        @Bindable var state = navState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSidebar)
        } detail: {
            Group {
                switch state.selectedSidebar ?? .allAnime {
                case .allAnime:
                    LibraryContainerView(watchStatusFilter: nil)
                case .watchStatus(let status):
                    LibraryContainerView(watchStatusFilter: status)
                case .search:
                    DiscoverView()
                case .weeklyCalendar:
                    WeeklyCalendarView()
                case .sequelAlerts:
                    SequelAlertsView()
                case .backup:
                    BackupManagementView()
                }
            }
            .inspector(isPresented: $state.showInspector) {
                ZStack {
                    AmbientGlowBackground()

                    Group {
                        if let anime = selectedAnime {
                            AnimeDetailInspectorView(anime: anime) {
                                modelContext.delete(anime)
                                try? modelContext.save()
                                state.selectedAnimeID = nil
                            }
                            .id(anime.persistentModelID)
                        } else if let dto = state.selectedJikanDTO {
                            JikanAnimeDetailInspectorView(dto: dto) { newAnime in
                                withAnimation(.spring(response: 0.3)) {
                                    state.selectTracked(newAnime.persistentModelID)
                                }
                            }
                            .id(dto.malId)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "sidebar.trailing")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("No Anime Selected")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("Click any anime in your Library, Search, or Weekly Calendar to view full details.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))

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
                }
                .inspectorColumnWidth(min: 290, ideal: 340, max: 430)
            }
        }
        .onAppear {
            _ = CloudSyncService.shared.autoRestoreIfLibraryEmpty(context: modelContext)
            CloudSyncService.shared.performAutoCloudBackup(from: allAnime)
        }
        .onChange(of: allAnime.count) {
            CloudSyncService.shared.performAutoCloudBackup(from: allAnime)
        }
    }
}
