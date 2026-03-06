import SwiftUI
import SwiftData

enum SortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case name = "Name"
    case size = "Size"
    case status = "Status"
    case priority = "Priority"

    var localizedName: String {
        switch self {
        case .dateAdded: return NSLocalizedString("sort.dateAdded", comment: "")
        case .name: return NSLocalizedString("sort.name", comment: "")
        case .size: return NSLocalizedString("sort.size", comment: "")
        case .status: return NSLocalizedString("sort.status", comment: "")
        case .priority: return NSLocalizedString("sort.priority", comment: "")
        }
    }
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
    @AppStorage(Constants.Keys.deleteConfirmation) private var deleteConfirmation = "ask"
    @State private var showDeleteSheet = false
    @State private var pendingDeleteItem: DownloadItem?
    @State private var rememberDeleteChoice = false

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
                                requestDelete(item)
                            })
                                .contentShape(Rectangle())
                                .background(rowBackground(item))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                .onTapGesture(count: 2) {
                                    if item.status == .completed {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath))
                                    }
                                }
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
        .alert(NSLocalizedString("action.renameFile", comment: ""), isPresented: $showRenameAlert) {
            TextField(NSLocalizedString("action.renameFilePlaceholder", comment: ""), text: $renameText)
            Button(NSLocalizedString("action.rename", comment: "")) { performRename() }
            Button(NSLocalizedString("action.cancel", comment: ""), role: .cancel) {}
        }
        .sheet(isPresented: $showScheduleSheet) {
            scheduleSheet
        }
        .sheet(isPresented: $showDeleteSheet) {
            deleteConfirmationSheet
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

                Text(String(format: NSLocalizedString("list.itemCount", comment: ""), filteredItems.count))
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
                    .help(NSLocalizedString("action.delete", comment: ""))
                }

                if !downloadManager.activeDownloads.isEmpty {
                    SpeedBadge(speed: downloadManager.totalSpeed)
                }

                if allItems.contains(where: { $0.status == .downloading }) {
                    Button(action: { downloadManager.pauseAll() }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.warning)
                            .frame(width: 28, height: 28)
                            .background(Theme.warning.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("action.pauseAll", comment: ""))
                }

                if allItems.contains(where: { $0.status == .paused || $0.status == .waiting }) {
                    Button(action: {
                        let items = allItems.filter { $0.status == .paused || $0.status == .waiting }
                        for item in items {
                            if item.status == .paused {
                                downloadManager.resumeDownload(item: item, force: true)
                            } else {
                                downloadManager.forceStartDownload(item: item)
                            }
                        }
                    }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("action.resumeAll", comment: ""))
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
                    .help(NSLocalizedString("action.clearAll", comment: ""))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("sort.label", comment: ""))
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
                        Text(option.localizedName)
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
            TextField(NSLocalizedString("list.searchPlaceholder", comment: ""), text: $searchText)
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
                Text(NSLocalizedString("schedule.title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(NSLocalizedString("action.cancel", comment: "")) { showScheduleSheet = false }
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

            DatePicker(NSLocalizedString("schedule.startAt", comment: ""), selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)

            HStack {
                Spacer()
                Button(NSLocalizedString("action.schedule", comment: "")) {
                    performSchedule()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var deleteConfirmationSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("delete.confirmTitle", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: { showDeleteSheet = false; pendingDeleteItem = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if let item = pendingDeleteItem {
                HStack(spacing: 10) {
                    CategoryIcon(category: item.category, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        if item.fileExists {
                            Text(item.destinationPath)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Theme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(NSLocalizedString("delete.confirmMessage", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $rememberDeleteChoice) {
                Text(NSLocalizedString("delete.rememberChoice", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button(action: { showDeleteSheet = false; pendingDeleteItem = nil }) {
                    Text(NSLocalizedString("action.cancel", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.vertical, 8)
                .background(Theme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: {
                    if let item = pendingDeleteItem {
                        if rememberDeleteChoice { deleteConfirmation = "removeOnly" }
                        deleteItem(item)
                    }
                    showDeleteSheet = false
                    pendingDeleteItem = nil
                }) {
                    Text(NSLocalizedString("action.removeFromList", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .background(Theme.warning)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if pendingDeleteItem?.fileExists == true {
                    Button(action: {
                        if let item = pendingDeleteItem {
                            if rememberDeleteChoice { deleteConfirmation = "deleteFile" }
                            deleteItemWithFile(item)
                        }
                        showDeleteSheet = false
                        pendingDeleteItem = nil
                    }) {
                        Text(NSLocalizedString("action.deleteFile", comment: ""))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Theme.error)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Titles

    private var headerTitle: String {
        switch selectedFilter {
        case .all: return NSLocalizedString("sidebar.all", comment: "")
        case .active: return NSLocalizedString("sidebar.active", comment: "")
        case .completed: return NSLocalizedString("sidebar.completed", comment: "")
        case .scheduled: return NSLocalizedString("sidebar.scheduled", comment: "")
        case .history: return NSLocalizedString("sidebar.history", comment: "")
        case .category(let cat): return cat.localizedName
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
        case .active: return NSLocalizedString("empty.noActive", comment: "")
        case .completed: return NSLocalizedString("empty.noCompleted", comment: "")
        case .scheduled: return NSLocalizedString("empty.noScheduled", comment: "")
        default: return NSLocalizedString("empty.noDownloads", comment: "")
        }
    }

    private var emptySubtitle: String {
        NSLocalizedString("empty.subtitle", comment: "")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: DownloadItem) -> some View {
        if item.status == .downloading {
            Button(NSLocalizedString("action.pause", comment: "")) { downloadManager.pauseDownload(item: item) }
            Button(NSLocalizedString("action.cancel", comment: "")) { downloadManager.cancelDownload(item: item) }
        }
        if item.status == .paused {
            Button(NSLocalizedString("action.resume", comment: "")) { downloadManager.resumeDownload(item: item, force: true) }
            Button(NSLocalizedString("action.cancel", comment: "")) { downloadManager.cancelDownload(item: item) }
        }
        if item.status == .waiting {
            Button(NSLocalizedString("action.startNow", comment: "")) { downloadManager.forceStartDownload(item: item) }
            Button(NSLocalizedString("action.cancel", comment: "")) { downloadManager.cancelDownload(item: item) }
        }
        if item.status == .failed || item.status == .cancelled {
            Button(NSLocalizedString("action.retry", comment: "")) { downloadManager.retryDownload(item: item) }
        }
        if item.status == .completed {
            Button(NSLocalizedString("action.showInFinder", comment: "")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.destinationPath)])
            }
            Button(NSLocalizedString("action.open", comment: "")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath))
            }
        }

        Divider()

        // Rename
        Button(NSLocalizedString("action.rename", comment: "")) {
            renamingItem = item
            renameText = item.fileName
            showRenameAlert = true
        }

        // Priority
        Divider()
        Text(NSLocalizedString("priority.label", comment: ""))
        ForEach(DownloadPriority.allCases, id: \.self) { p in
            Button {
                item.priority = p
                try? modelContext.save()
                downloadManager.refreshScheduling()
            } label: {
                HStack {
                    Image(systemName: p.icon)
                    Text(p.localizedName)
                    if item.safePriority == p {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        // Schedule
        if item.status == .waiting || item.status == .paused || item.status == .cancelled || item.status == .failed {
            Button(NSLocalizedString("action.schedule", comment: "")) {
                schedulingItem = item
                scheduleDate = Date().addingTimeInterval(3600) // default 1h from now
                showScheduleSheet = true
            }
        }

        if item.status == .scheduled {
            Button(NSLocalizedString("action.startNow", comment: "")) {
                item.status = .waiting
                item.scheduledDate = nil
                try? modelContext.save()
                downloadManager.startDownload(item: item)
            }
        }

        Divider()

        Button(NSLocalizedString("action.copyURL", comment: "")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        // Remove from list only (keep file)
        Button(NSLocalizedString("action.removeFromList", comment: "")) {
            requestDelete(item)
        }

        // Delete file from disk + remove from list
        if item.status == .completed && item.fileExists {
            Button(NSLocalizedString("action.deleteFile", comment: ""), role: .destructive) {
                deleteItemWithFile(item)
            }
        }
    }

    // MARK: - Actions

    private func performRename() {
        guard let item = renamingItem, !renameText.isEmpty, renameText != item.fileName else {
            renamingItem = nil
            return
        }
        let oldPath = item.destinationPath
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(renameText)

        // Rename the file on disk if it exists
        if FileManager.default.fileExists(atPath: oldPath) {
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
        }

        item.fileName = renameText
        item.destinationPath = newURL.path
        try? modelContext.save()
        renamingItem = nil
    }

    private func performSchedule() {
        guard let item = schedulingItem else { return }
        if item.status == .waiting {
            downloadManager.removeFromPendingQueue(itemId: item.id)
        }

        if item.status == .downloading {
            downloadManager.pauseDownload(item: item)
        }

        item.status = .scheduled
        item.errorMessage = nil
        item.scheduledDate = scheduleDate
        try? modelContext.save()

        // SchedulerService timer will pick this up when the time arrives
        showScheduleSheet = false
        schedulingItem = nil
    }

    private func deleteItem(_ item: DownloadItem) {
        downloadManager.prepareForRemoval(item: item)
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        selectedItems.remove(item.id)
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func deleteItemWithFile(_ item: DownloadItem) {
        downloadManager.prepareForRemoval(item: item, deleteCompletedFile: true)
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        selectedItems.remove(item.id)
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func requestDelete(_ item: DownloadItem) {
        // If user has a saved preference, act immediately
        switch deleteConfirmation {
        case "removeOnly":
            deleteItem(item)
        case "deleteFile":
            deleteItemWithFile(item)
        default:
            // "ask" — show confirmation sheet
            pendingDeleteItem = item
            rememberDeleteChoice = false
            showDeleteSheet = true
        }
    }

    private func deleteSelectedItems() {
        for id in selectedItems {
            if let item = allItems.first(where: { $0.id == id }) {
                if deleteConfirmation == "deleteFile" {
                    deleteItemWithFile(item)
                } else {
                    deleteItem(item)
                }
            }
        }
        selectedItems.removeAll()
    }

    private func clearAllDownloads() {
        for item in allItems {
            downloadManager.prepareForRemoval(item: item)
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedItem = nil
        selectedItems.removeAll()
    }
}
