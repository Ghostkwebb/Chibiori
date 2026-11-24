import SwiftUI
import SwiftData

public enum FranchiseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case main = "Main Story"
    case movies = "Movies"
    case ovas = "OVAs & Specials"

    public var id: String { rawValue }
}

@MainActor
public struct FranchiseHubSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationState.self) private var navState
    @Environment(LibraryStore.self) private var libraryStore

    let currentMalID: Int
    let currentTitle: String
    let currentEnglishTitle: String?

    @State private var franchiseItems: [RelatedAnimeItem] = []
    @State private var isLoading = true
    @State private var selectedFilter: FranchiseFilter = .all
    @State private var searchText = ""

    public init(
        currentMalID: Int,
        currentTitle: String,
        currentEnglishTitle: String? = nil
    ) {
        self.currentMalID = currentMalID
        self.currentTitle = currentTitle
        self.currentEnglishTitle = currentEnglishTitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .opacity(0.4)

            // Search & Filter Tabs
            controlsSection
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.3)

            // Content Area
            if isLoading && franchiseItems.isEmpty {
                loadingView
            } else if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsListView
            }
        }
        .frame(minWidth: 680, idealWidth: 740, maxWidth: 880, minHeight: 560, idealHeight: 620, maxHeight: 820)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.85)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        )
        .task {
            await loadFranchise()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.4), Color.indigo.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise Hub")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(currentTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Refresh Button
            Button {
                Task {
                    await loadFranchise(forceRefresh: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("Refresh franchise media from network")

            // Done Button
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Filter & Search Controls
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search franchise media...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )

            // Filter Tabs
            HStack(spacing: 8) {
                ForEach(FranchiseFilter.allCases) { filter in
                    let count = count(for: filter)
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: selectedFilter == filter ? .bold : .medium))
                            Text("\(count)")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    selectedFilter == filter
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedFilter == filter
                            ? Color.purple.opacity(0.35)
                            : Color.white.opacity(0.05)
                        )
                        .foregroundStyle(selectedFilter == filter ? Color.white : Color.secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedFilter == filter ? Color.purple.opacity(0.6) : Color.white.opacity(0.1),
                                    lineWidth: 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
    }

    // MARK: - List View
    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredItems) { item in
                    let match = libraryStore.findMatchingTracked(
                        malID: item.malID,
                        title: item.title,
                        englishTitle: item.englishTitle
                    )
                    FranchiseItemRow(
                        item: item,
                        isCurrent: (item.malID > 0 && item.malID == currentMalID) || item.title.localizedCaseInsensitiveCompare(currentTitle) == .orderedSame,
                        trackedMatch: match,
                        titlePreference: navState.titleLanguagePreference,
                        onInspect: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                if let match {
                                    navState.navigateTo(tracked: match)
                                } else {
                                    navState.navigateTo(dto: item.asJikanDTO)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Discovering franchise media...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text("No Media Found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("No entries match \"\(searchText)\" in this category.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No related franchise entries are available for this section.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
    private func loadFranchise(forceRefresh: Bool = false) async {
        isLoading = true
        let allSnapshots = libraryStore.allAnime.map(\.matchSnapshot)
        let items = await AnimeRelationsService.shared.fetchFullFranchise(
            malID: currentMalID,
            title: currentTitle,
            englishTitle: currentEnglishTitle,
            allLibrary: allSnapshots,
            forceRefresh: forceRefresh
        )
        self.franchiseItems = items
        self.isLoading = false
    }

    private var filteredItems: [RelatedAnimeItem] {
        var list = franchiseItems
        switch selectedFilter {
        case .all:
            break
        case .main:
            list = list.filter { item in
                let t = item.relationType.uppercased()
                return t == "CURRENT" || t == "PREQUEL" || t == "SEQUEL" || t == "MAIN_STORY" || t == "SEASON" || t == "PARENT" || item.format == "TV"
            }
        case .movies:
            list = list.filter { item in
                item.relationType.uppercased() == "MOVIE" || item.format == "MOVIE"
            }
        case .ovas:
            list = list.filter { item in
                let t = item.relationType.uppercased()
                let f = item.format?.uppercased() ?? ""
                return t == "OVA" || t == "ONA" || t == "SPECIAL" || t == "SIDE_STORY" || t == "SPIN_OFF" || f == "OVA" || f == "ONA" || f == "SPECIAL"
            }
        }

        let cleanQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanQuery.isEmpty {
            list = list.filter { item in
                item.title.lowercased().contains(cleanQuery) ||
                (item.englishTitle?.lowercased().contains(cleanQuery) ?? false) ||
                item.relationDisplayName.lowercased().contains(cleanQuery) ||
                (item.format?.lowercased().contains(cleanQuery) ?? false)
            }
        }

        return list
    }

    private func count(for filter: FranchiseFilter) -> Int {
        switch filter {
        case .all:
            return franchiseItems.count
        case .main:
            return franchiseItems.filter { item in
                let t = item.relationType.uppercased()
                return t == "CURRENT" || t == "PREQUEL" || t == "SEQUEL" || t == "MAIN_STORY" || t == "SEASON" || t == "PARENT" || item.format == "TV"
            }.count
        case .movies:
            return franchiseItems.filter { item in
                item.relationType.uppercased() == "MOVIE" || item.format == "MOVIE"
            }.count
        case .ovas:
            return franchiseItems.filter { item in
                let t = item.relationType.uppercased()
                let f = item.format?.uppercased() ?? ""
                return t == "OVA" || t == "ONA" || t == "SPECIAL" || t == "SIDE_STORY" || t == "SPIN_OFF" || f == "OVA" || f == "ONA" || f == "SPECIAL"
            }.count
        }
    }
}
