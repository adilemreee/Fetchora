import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreSpotlight

enum SheetType: Identifiable {
    case addURL
    case settings
    case bulkURL
    case clipboard
    case duplicateURL
    case duplicateFile

    var id: String {
        switch self {
        case .addURL: return "addURL"
        case .settings: return "settings"
        case .bulkURL: return "bulkURL"
        case .clipboard: return "clipboard"
        case .duplicateURL: return "duplicateURL"
        case .duplicateFile: return "duplicateFile"
        }
    }
}

struct ContentView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var clipboardMonitor = ClipboardMonitor.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(Constants.Keys.themeMode) private var themeMode = "system"
    @AppStorage(Constants.Keys.autoRemoveDeletedFiles) private var autoRemoveDeletedFiles = false
    @AppStorage(Constants.Keys.autoRemoveCompleted) private var autoRemoveCompleted = false
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedItem: DownloadItem?
    @State private var searchText = ""
    @State private var activeSheet: SheetType?
    @State private var newURLText = ""
    @State private var bulkURLText = ""
    @State private var isDragOver = false
    @State private var duplicateURL = ""
    @State private var duplicateExistingItem: DownloadItem?
    @State private var showFileImporter = false
    @State private var duplicateFileName = ""
    @State private var duplicateFileURLString = ""
    @State private var duplicateFilePath = ""
    @State private var rememberDuplicateFileChoice = false
    @State private var pendingSheet: SheetType?
    @AppStorage("duplicateFileDefaultAction") private var duplicateFileDefaultAction = "" // "", "rename", "overwrite"
    @Query private var allDownloadItems: [DownloadItem]
    @Environment(\.modelContext) private var modelContext

    private var activeCount: Int { allDownloadItems.filter { $0.status == .downloading || $0.status == .waiting || $0.status == .paused }.count }
    private var completedCount: Int { allDownloadItems.filter { $0.status == .completed }.count }
    private var failedCount: Int { allDownloadItems.filter { $0.status == .failed }.count }

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                mainView
            }
        }
    }

    private var mainView: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 280)
        } detail: {
            if let item = selectedItem {
                // Show detail when an item is selected
                HStack(spacing: 0) {
                    downloadListPanel
                    Divider().background(Theme.border)
                    DownloadDetailView(item: item, onClose: { selectedItem = nil })
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 320)
                }
            } else {
                // Full width list when nothing selected
                downloadListPanel
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Button(action: { activeSheet = .addURL }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .help(NSLocalizedString("action.addDownload", comment: ""))

                    Button(action: { importTXTFile() }) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .help(NSLocalizedString("action.importFile", comment: ""))
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addURL:
                addURLSheet
            case .settings:
                SettingsView()
                    .frame(width: 680, height: 520)
                    .preferredColorScheme(themeColorScheme)
            case .bulkURL:
                bulkURLSheet
            case .clipboard:
                clipboardPromptSheet
            case .duplicateURL:
                duplicateURLSheet
            case .duplicateFile:
                duplicateFileSheet
            }
        }
        .onChange(of: activeSheet) { oldVal, newVal in
            // When a sheet dismisses, check if there's a pending sheet to show
            if newVal == nil, let pending = pendingSheet {
                pendingSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    activeSheet = pending
                }
            }
        }
        .onAppear {
            setupDownloadManager()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("clearAllDownloads"))) { _ in
            clearAllDownloads()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("addDownloadURL"))) { notification in
            if let urlString = notification.userInfo?["url"] as? String {
                addDownloadByURLString(urlString)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.downloadCompleted)) { notification in
            guard autoRemoveCompleted,
                  let itemId = notification.userInfo?["itemId"] as? UUID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let descriptor = FetchDescriptor<DownloadItem>(predicate: #Predicate { $0.id == itemId })
                if let item = try? modelContext.fetch(descriptor).first, item.status == .completed {
                    if selectedItem?.id == item.id { selectedItem = nil }
                    modelContext.delete(item)
                    try? modelContext.save()
                }
            }
        }
        .task {
            // Periodic check: remove items whose files were deleted from disk
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if autoRemoveDeletedFiles {
                    removeDeletedFileItems()
                }
            }
        }
        // Drag & Drop URL
        .onDrop(of: [.url, .text], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDragOver {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Theme.primary)
                        Text(NSLocalizedString("drop.urlToDownload", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        // Keyboard shortcuts
        .keyboardShortcut("n", modifiers: .command)
        .preferredColorScheme(themeColorScheme)
        .onReceive(clipboardMonitor.$showURLPrompt) { show in
            if show {
                clipboardMonitor.showURLPrompt = false
                showSheet(.clipboard)
            }
        }
        .onAppear {
            clipboardMonitor.startMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("loadDemoData"))) { _ in
            PreviewHelper.populateDemoData(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("clearDemoData"))) { _ in
            PreviewHelper.clearDemoData(context: modelContext)
        }
    }

    private var themeColorScheme: ColorScheme? {
        switch themeMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    // MARK: - Download List Panel

    private var downloadListPanel: some View {
        DownloadListView(
            selectedFilter: $selectedFilter,
            searchText: $searchText,
            selectedItem: $selectedItem
        )
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // App branding
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.primaryGradient)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("app.name", comment: ""))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    if !downloadManager.activeDownloads.isEmpty {
                        Text(String(format: NSLocalizedString("menubar.activeCount", comment: ""), downloadManager.activeDownloads.count))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.accent)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Theme.border)

            // Filter sections
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader(NSLocalizedString("sidebar.downloads", comment: ""))

                    sidebarRow(title: NSLocalizedString("sidebar.all", comment: ""), icon: "arrow.down.circle", filter: .all, isSelected: selectedFilter == .all, badge: allDownloadItems.count)
                    sidebarRow(title: NSLocalizedString("sidebar.active", comment: ""), icon: "arrow.down.circle.fill", filter: .active, isSelected: selectedFilter == .active, badge: activeCount)
                    sidebarRow(title: NSLocalizedString("sidebar.completed", comment: ""), icon: "checkmark.circle.fill", filter: .completed, isSelected: selectedFilter == .completed, badge: completedCount)
                    sidebarRow(title: NSLocalizedString("sidebar.scheduled", comment: ""), icon: "calendar.circle", filter: .scheduled, isSelected: selectedFilter == .scheduled)
                    sidebarRow(title: NSLocalizedString("sidebar.history", comment: ""), icon: "clock.arrow.circlepath", filter: .history, isSelected: selectedFilter == .history)

                    Divider().background(Theme.border).padding(.vertical, 8)

                    sectionHeader(NSLocalizedString("sidebar.categories", comment: ""))

                    ForEach(DownloadCategory.fileCategories) { category in
                        let count = allDownloadItems.filter { $0.category.rawValue == category.name }.count
                        sidebarRow(
                            title: category.name,
                            icon: category.icon,
                            filter: category.filter,
                            isSelected: selectedFilter == category.filter,
                            badge: count > 0 ? count : nil
                        )
                    }

                }
                .padding(8)
            }

            Divider().background(Theme.border)

            // Settings button
            Button {
                activeSheet = .settings
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 20)
                    Text(NSLocalizedString("settings.title", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .background(Theme.surfaceSecondary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func sidebarRow(title: String, icon: String, filter: SidebarFilter, isSelected: Bool, badge: Int? = nil) -> some View {
        Button {
            withAnimation(Theme.quickAnimation) {
                selectedFilter = filter
                selectedItem = nil
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Theme.primary : Theme.textTertiary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Spacer()

                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Theme.primary : Theme.textTertiary.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.primary.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add URL Sheet

    private var addURLSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("addDownload.title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(NSLocalizedString("addDownload.bulk", comment: "")) { activeSheet = .bulkURL }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
                Button(NSLocalizedString("action.cancel", comment: "")) { activeSheet = nil }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
            }

            TextField(NSLocalizedString("addDownload.placeholder", comment: ""), text: $newURLText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            HStack {
                Spacer()
                Button(NSLocalizedString("action.download", comment: "")) {
                    addDownloadFromURL()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newURLText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Bulk URL Sheet

    private var bulkURLSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("addDownload.bulkTitle", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(NSLocalizedString("action.cancel", comment: "")) { activeSheet = nil }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
            }

            Text(NSLocalizedString("addDownload.bulkDescription", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $bulkURLText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 160)
                .border(Theme.border, width: 1)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                let count = bulkURLText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.hasPrefix("http") }.count
                Text(String(format: NSLocalizedString("addDownload.urlsDetected", comment: ""), count))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                Button(NSLocalizedString("action.downloadAll", comment: "")) {
                    addBulkDownloads()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bulkURLText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    // MARK: - Clipboard Prompt

    private var clipboardPromptSheet: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("clipboard.detected", comment: ""))
                        .font(.system(size: 14, weight: .bold))
                    Text(clipboardMonitor.detectedURL ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button(NSLocalizedString("action.ignore", comment: "")) {
                    clipboardMonitor.ignoreCurrentURL()
                    activeSheet = nil
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)
                Button(NSLocalizedString("action.download", comment: "")) {
                    let url = clipboardMonitor.detectedURL
                    clipboardMonitor.ignoreCurrentURL()
                    activeSheet = nil
                    if let url = url {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            addDownloadByURLString(url)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Duplicate URL Sheet

    private var duplicateURLSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text(NSLocalizedString("duplicate.download.title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: { activeSheet = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            // Info card
            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: NSLocalizedString("detail.url", comment: ""), value: duplicateURL)

                if let existing = duplicateExistingItem {
                    Divider().background(Theme.border)
                    infoRow(label: NSLocalizedString("duplicate.path", comment: ""), value: existing.destinationPath)

                    if existing.totalBytes > 0 {
                        Divider().background(Theme.border)
                        infoRow(label: NSLocalizedString("duplicate.size", comment: ""), value: existing.totalBytes.formattedFileSize)
                    }

                    Divider().background(Theme.border)
                    infoRow(label: NSLocalizedString("duplicate.dateAdded", comment: ""), value: existing.dateAdded.shortFormatted)
                }
            }
            .padding(14)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.bottom, 20)

            // Buttons
            HStack(spacing: 10) {
                Spacer()
                Button(action: { activeSheet = nil }) {
                    Text(NSLocalizedString("duplicate.skip", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: {
                    let url = duplicateURL
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        addDownloadByURLString(url, skipDuplicateCheck: true)
                    }
                }) {
                    Text(NSLocalizedString("duplicate.download", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    // MARK: - Duplicate File Sheet

    private var duplicateFileSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text(NSLocalizedString("duplicate.file.title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: { activeSheet = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            // Path card
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.primary)
                Text(duplicateFilePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.bottom, 14)

            // Remember toggle
            Toggle(isOn: $rememberDuplicateFileChoice) {
                Text(NSLocalizedString("duplicate.rememberChoice", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 18)

            // Buttons
            HStack(spacing: 10) {
                Spacer()

                Button(action: {
                    if rememberDuplicateFileChoice { duplicateFileDefaultAction = "rename" }
                    let url = duplicateFileURLString
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        addDownloadByURLString(url, skipDuplicateCheck: true, skipFileNameCheck: true, autoRename: true)
                    }
                }) {
                    Text(NSLocalizedString("duplicate.rename", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: {
                    if rememberDuplicateFileChoice { duplicateFileDefaultAction = "overwrite" }
                    let url = duplicateFileURLString
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        addDownloadByURLString(url, skipDuplicateCheck: true, skipFileNameCheck: true)
                    }
                }) {
                    Text(NSLocalizedString("duplicate.overwrite", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: { activeSheet = nil }) {
                    Text(NSLocalizedString("duplicate.cancel", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: - Sheet Management
    
    private func showSheet(_ type: SheetType) {
        if activeSheet != nil {
            // Another sheet is open — queue this one
            pendingSheet = type
            activeSheet = nil
        } else {
            activeSheet = type
        }
    }

    // MARK: - Helpers

    private func setupDownloadManager() {
        downloadManager.findItem = { [self] id in
            let descriptor = FetchDescriptor<DownloadItem>(predicate: #Predicate { $0.id == id })
            return try? modelContext.fetch(descriptor).first
        }

        // Wire up SchedulerService to use SwiftData items
        let scheduler = SchedulerService.shared
        scheduler.fetchScheduledItems = { [self] in
            let scheduledStatus = DownloadStatus.scheduled
            let descriptor = FetchDescriptor<DownloadItem>(predicate: #Predicate { $0.status == scheduledStatus })
            return (try? modelContext.fetch(descriptor)) ?? []
        }
        scheduler.startDownloadHandler = { [weak downloadManager] item in
            downloadManager?.startDownload(item: item)
        }
    }

    private func addDownloadFromURL() {
        let url = newURLText
        newURLText = ""
        activeSheet = nil
        pendingSheet = nil
        // Delay so the add-URL sheet fully dismisses before a duplicate sheet can present
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.addDownloadByURLString(url)
        }
    }

    private func addBulkDownloads() {
        let urls = bulkURLText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("http") }

        bulkURLText = ""
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for urlString in urls {
                self.addDownloadByURLString(urlString)
            }
        }
    }

    private func clearAllDownloads() {
        downloadManager.pauseAll()

        let descriptor = FetchDescriptor<DownloadItem>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items {
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
        selectedItem = nil
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            addDownloadByURLString(url.absoluteString)
                        }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, _ in
                    if let text = item as? String, text.hasPrefix("http") {
                        DispatchQueue.main.async {
                            addDownloadByURLString(text)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func addDownloadByURLString(_ urlString: String, skipDuplicateCheck: Bool = false, skipFileNameCheck: Bool = false, autoRename: Bool = false) {
        guard let url = URL(string: urlString) else { return }

        // Duplicate URL detection
        if !skipDuplicateCheck {
            if let existing = allDownloadItems.first(where: { $0.url == urlString }) {
                duplicateURL = urlString
                duplicateExistingItem = existing
                showSheet(.duplicateURL)
                return
            }
        }

        var fileName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent

        // Duplicate filename detection
        if !skipFileNameCheck {
            if allDownloadItems.contains(where: { $0.fileName == fileName }) {
                let dest = FileOrganizer.shared.destinationURL(for: fileName)
                duplicateFileName = fileName
                duplicateFileURLString = urlString
                duplicateFilePath = dest.path

                // Auto-apply remembered choice
                if duplicateFileDefaultAction == "rename" {
                    addDownloadByURLString(urlString, skipDuplicateCheck: true, skipFileNameCheck: true, autoRename: true)
                    return
                } else if duplicateFileDefaultAction == "overwrite" {
                    addDownloadByURLString(urlString, skipDuplicateCheck: true, skipFileNameCheck: true)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showSheet(.duplicateFile)
                }
                return
            }
        }

        // Auto-rename: append (1), (2), etc.
        if autoRename {
            let baseName = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            var counter = 1
            while allDownloadItems.contains(where: { $0.fileName == fileName }) {
                fileName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                counter += 1
            }
        }

        let destination = FileOrganizer.shared.destinationURL(for: fileName)
        let category = FileCategory.from(extension: url.fileExtensionLowercased)

        let item = DownloadItem(
            url: urlString,
            fileName: fileName,
            destinationPath: destination.path,
            category: category
        )
        modelContext.insert(item)
        try? modelContext.save()
        downloadManager.startDownload(item: item)

        // Spotlight indexing
        indexForSpotlight(item: item)
    }

    private func importTXTFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.title = NSLocalizedString("action.importFile", comment: "")

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let urls = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("http") }

        for urlString in urls {
            addDownloadByURLString(urlString)
        }
    }

    private func indexForSpotlight(item: DownloadItem) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .data)
        attributeSet.title = item.fileName
        attributeSet.contentDescription = item.url
        attributeSet.addedDate = item.dateAdded

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: "com.adilemre.SwiftDownloader",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([searchableItem])
    }

    private func removeDeletedFileItems() {
        let completedItems = allDownloadItems.filter { $0.status == .completed }
        for item in completedItems {
            if !item.destinationPath.isEmpty && !FileManager.default.fileExists(atPath: item.destinationPath) {
                if selectedItem?.id == item.id { selectedItem = nil }
                modelContext.delete(item)
            }
        }
        try? modelContext.save()
    }
}
