import SwiftUI
import SwiftData

enum SortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case name = "Name"
    case size = "Size"
    case status = "Status"
    case priority = "Priority"
}

struct DownloadListView: View {
    @Query(sort: \DownloadItem.dateAdded, order: .reverse) private var allItems: [DownloadItem]
    @ObservedObject var downloadManager = DownloadManager.shared
    @Binding var selectedFilter: SidebarFilter
    @Binding var searchText: String
    @Binding var selectedItem: DownloadItem?
    @Environment(\.modelContext) private var modelContext

    @State private var sortOption: SortOption = .dateAdded
    @State private var sortAscending = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var renamingItem: DownloadItem?
    @State private var showScheduleSheet = false
    @State private var schedulingItem: DownloadItem?
    @State private var scheduleDate = Date()
    @State private var selectedItems: Set<UUID> = []

    private var filteredItems: [DownloadItem] {
        let filtered = allItems.filter { item in
            let matchesFilter = selectedFilter.matches(item)
            let matchesSearch = searchText.isEmpty || item.fileName.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
        return sortItems(filtered)
    }

    private func sortItems(_ items: [DownloadItem]) -> [DownloadItem] {
        items.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .dateAdded: result = a.dateAdded > b.dateAdded
            case .name: result = a.fileName.localizedCaseInsensitiveCompare(b.fileName) == .orderedAscending
            case .size: result = a.totalBytes > b.totalBytes
            case .status: result = a.status.rawValue < b.status.rawValue
            case .priority: result = a.safePriority.sortOrder < b.safePriority.sortOrder
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            sortBar
            searchBar
            Divider().background(Theme.border)

            if filteredItems.isEmpty {
                EmptyStateView(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            DownloadRowView(item: item, onDelete: {
                                deleteItem(item)
                            })
                                .contentShape(Rectangle())
                                .background(rowBackground(item))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.command) {
                                        // Multi-select with ⌘
                                        if selectedItems.contains(item.id) {
                                            selectedItems.remove(item.id)
                                        } else {
                                            selectedItems.insert(item.id)
                                        }
                                    } else {
                                        withAnimation(Theme.quickAnimation) {
                                            selectedItems.removeAll()
                                            selectedItem = (selectedItem?.id == item.id) ? nil : item
                                        }
                                    }
                                }
                                .contextMenu {
                                    contextMenuItems(for: item)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Theme.surfacePrimary)
        .alert("Rename File", isPresented: $showRenameAlert) {
            TextField("File name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showScheduleSheet) {
            scheduleSheet
        }
    }

    private func rowBackground(_ item: DownloadItem) -> Color {
        if selectedItems.contains(item.id) {
            return Theme.primary.opacity(0.15)
        }
        if selectedItem?.id == item.id {
            return Theme.primary.opacity(0.1)
        }
        return Color.clear
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text("\(filteredItems.count) items")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                if !selectedItems.isEmpty {
                    Button(action: deleteSelectedItems) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("\(selectedItems.count)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Theme.error)
                        .frame(height: 28)
                        .padding(.horizontal, 8)
                        .background(Theme.error.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Delete Selected")
                }

                if !downloadManager.activeDownloads.isEmpty {
                    SpeedBadge(speed: downloadManager.totalSpeed)

                    Button(action: { downloadManager.pauseAll() }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.warning)
                            .frame(width: 28, height: 28)
                            .background(Theme.warning.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Pause All")
                }

                if !allItems.isEmpty {
                    Button(action: { clearAllDownloads() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.error)
                            .frame(width: 28, height: 28)
                            .background(Theme.error.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear All Downloads")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 6) {
            Text("Sort:")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)

            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    if sortOption == option {
                        sortAscending.toggle()
                    } else {
                        sortOption = option
                        sortAscending = false
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(option.rawValue)
                            .font(.system(size: 10, weight: sortOption == option ? .bold : .regular))
                        if sortOption == option {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                    }
                    .foregroundColor(sortOption == option ? Theme.primary : Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(sortOption == option ? Theme.primary.opacity(0.1) : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textTertiary)
                .font(.system(size: 12))
            TextField("Search downloads...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textTertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Schedule Sheet

    private var scheduleSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Schedule Download")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") { showScheduleSheet = false }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
            }

            if let item = schedulingItem {
                HStack(spacing: 10) {
                    CategoryIcon(category: item.category, size: 32)
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(10)
                .background(Theme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            DatePicker("Start at:", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)

            HStack {
                Spacer()
                Button("Schedule") {
                    performSchedule()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Titles

    private var headerTitle: String {
        switch selectedFilter {
        case .all: return "All Downloads"
        case .active: return "Active"
        case .completed: return "Completed"
        case .scheduled: return "Scheduled"
        case .history: return "History"
        case .category(let cat): return cat.rawValue
        }
    }

    private var emptyIcon: String {
        switch selectedFilter {
        case .active: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .scheduled: return "calendar.circle"
        default: return "tray"
        }
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .active: return "No Active Downloads"
        case .completed: return "No Completed Downloads"
        case .scheduled: return "No Scheduled Downloads"
        default: return "No Downloads"
        }
    }

    private var emptySubtitle: String {
        "Downloads from Safari will appear here.\nEnable the extension in Safari preferences."
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: DownloadItem) -> some View {
        if item.status == .downloading {
            Button("Pause") { downloadManager.pauseDownload(item: item) }
            Button("Cancel") { downloadManager.cancelDownload(item: item) }
        }
        if item.status == .paused {
            Button("Resume") { downloadManager.resumeDownload(item: item) }
            Button("Cancel") { downloadManager.cancelDownload(item: item) }
        }
        if item.status == .failed || item.status == .cancelled {
            Button("Retry") { downloadManager.retryDownload(item: item) }
        }
        if item.status == .completed {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.destinationPath)])
            }
            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath))
            }
        }

        Divider()

        // Rename
        Button("Rename...") {
            renamingItem = item
            renameText = item.fileName
            showRenameAlert = true
        }

        // Priority
        Menu("Priority") {
            ForEach(DownloadPriority.allCases, id: \.self) { p in
                Button {
                    item.priority = p
                    try? modelContext.save()
                } label: {
                    HStack {
                        Image(systemName: p.icon)
                        Text(p.rawValue)
                        if item.safePriority == p {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        // Schedule
        if item.status == .waiting || item.status == .paused || item.status == .cancelled || item.status == .failed {
            Button("Schedule...") {
                schedulingItem = item
                scheduleDate = Date().addingTimeInterval(3600) // default 1h from now
                showScheduleSheet = true
            }
        }

        if item.status == .scheduled {
            Button("Start Now") {
                item.status = .waiting
                item.scheduledDate = nil
                try? modelContext.save()
                downloadManager.startDownload(item: item)
            }
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            deleteItem(item)
        }
    }

    // MARK: - Actions

    private func performRename() {
        guard let item = renamingItem, !renameText.isEmpty else { return }
        item.fileName = renameText
        try? modelContext.save()
        renamingItem = nil
    }

    private func performSchedule() {
        guard let item = schedulingItem else { return }
        item.status = .scheduled
        item.scheduledDate = scheduleDate
        downloadManager.cancelDownload(item: item)
        item.status = .scheduled
        try? modelContext.save()

        // Start a timer
        let delay = scheduleDate.timeIntervalSinceNow
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak downloadManager] in
                guard item.status == .scheduled else { return }
                item.status = .waiting
                item.scheduledDate = nil
                downloadManager?.startDownload(item: item)
            }
        }
        showScheduleSheet = false
        schedulingItem = nil
    }

    private func deleteItem(_ item: DownloadItem) {
        if item.status == .downloading || item.status == .paused {
            downloadManager.cancelDownload(item: item)
        }
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        selectedItems.remove(item.id)
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func deleteSelectedItems() {
        for id in selectedItems {
            if let item = allItems.first(where: { $0.id == id }) {
                deleteItem(item)
            }
        }
        selectedItems.removeAll()
    }

    private func clearAllDownloads() {
        downloadManager.pauseAll()
        for item in allItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedItem = nil
        selectedItems.removeAll()
    }
}
