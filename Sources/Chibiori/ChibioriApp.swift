import SwiftUI
import SwiftData
import AppKit
import ChibioriCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var modelContainer: ModelContainer?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? modelContainer?.mainContext.save()
    }

    func applicationWillResignActive(_ notification: Notification) {
        try? modelContainer?.mainContext.save()
    }
}

@main
struct ChibioriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var navState = NavigationState()
    @State private var libraryStore: LibraryStore

    let container: ModelContainer

    init() {
        // Set macOS application dock icon from Chibiori_Logo.icns
        let workingDirIcon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Chibiori_Logo.icns")
        let icnsURL = Bundle.main.url(forResource: "Chibiori_Logo", withExtension: "icns")
            ?? Bundle.main.resourceURL?.appendingPathComponent("Chibiori_Logo.icns")
            ?? workingDirIcon
        if let iconImage = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        do {
            let schema = Schema([
                TrackedAnime.self
            ])
            // Local-only SQLite storage. iCloud sync is handled by CloudSyncService
            // which writes a JSON file directly to iCloud Drive — no developer account needed.
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            self.container = modelContainer
            self._libraryStore = State(initialValue: LibraryStore(modelContext: modelContainer.mainContext))
            self.appDelegate.modelContainer = modelContainer
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(navState)
                .environment(libraryStore)
                .modelContainer(container)
                .background(WindowAccessor())
                .frame(minWidth: 780, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateManager.shared.checkForUpdates(manual: true)
                }
            }

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

                Menu("Title Language") {
                    ForEach(TitleLanguagePreference.allCases) { pref in
                        Button {
                            navState.titleLanguagePreference = pref
                        } label: {
                            HStack {
                                Text(pref.displayName)
                                if navState.titleLanguagePreference == pref {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Menu("Grid Poster Size") {
                    Button("Zoom In") {
                        navState.zoomInGrid()
                    }
                    .keyboardShortcut("+", modifiers: [.command])

                    Button("Zoom Out") {
                        navState.zoomOutGrid()
                    }
                    .keyboardShortcut("-", modifiers: [.command])

                    Button("Actual Size (165 pt)") {
                        navState.resetGridSize()
                    }
                    .keyboardShortcut("0", modifiers: [.command])

                    Divider()

                    Button("Small (120 pt)") {
                        navState.gridCardSize = 120
                    }
                    Button("Medium / Default (165 pt)") {
                        navState.gridCardSize = 165
                    }
                    Button("Large (210 pt)") {
                        navState.gridCardSize = 210
                    }
                    Button("Hero (260 pt)") {
                        navState.gridCardSize = 260
                    }
                }

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
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.modelContext) private var modelContext

    // Initial column widths loaded once at launch from UserDefaults
    private let initialSidebarWidth: CGFloat
    private let initialInspectorWidth: CGFloat

    init() {
        let savedSidebar = UserDefaults.standard.double(forKey: "savedSidebarWidth")
        self.initialSidebarWidth = (savedSidebar >= 200 && savedSidebar <= 320) ? savedSidebar : 235

        let savedInspector = UserDefaults.standard.double(forKey: "savedInspectorWidth")
        self.initialInspectorWidth = (savedInspector >= 280 && savedInspector <= 480) ? savedInspector : 340
    }

    private var selectedAnime: TrackedAnime? {
        libraryStore.anime(for: navState.selectedAnimeID)
    }

    var body: some View {
        @Bindable var state = navState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: initialSidebarWidth, max: 320)
        } detail: {
            Group {
                switch state.selectedSidebar ?? .allAnime {
                case .allAnime, .watchStatus(_):
                    LibraryContainerView(watchStatusFilter: state.selectedSidebar?.filterStatus)
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
        }
        .inspector(isPresented: $state.showInspector) {
            Group {
                if let anime = selectedAnime {
                    AnimeDetailInspectorView(anime: anime) {
                        libraryStore.delete(anime)
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
            .background(.ultraThinMaterial)
            .inspectorColumnWidth(min: 280, ideal: initialInspectorWidth, max: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if CloudSyncService.shared.autoRestoreIfLibraryEmpty(context: modelContext) {
                libraryStore.reload()
            }
            CloudSyncService.shared.backupIfNeeded(from: libraryStore.allAnime)
            UpdateManager.shared.checkForUpdates(manual: false)
        }
        .sheet(isPresented: Bindable(UpdateManager.shared).showUpdateSheet) {
            UpdateModalView()
        }
    }
}
