import SwiftUI
import SwiftData

@main
struct SwiftDownloaderApp: App {
    @StateObject private var downloadManager = DownloadManager.shared
    @AppStorage(Constants.Keys.showMenuBarIcon) private var showMenuBar = true
    @AppStorage(Constants.Keys.themeMode) private var themeMode = "system"

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private var nsAppearance: NSAppearance? {
        switch themeMode {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([DownloadItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Main Window
        WindowGroup(id: "main") {
            ContentView()
                .id(themeMode)
                .frame(minWidth: 900, minHeight: 600)
                .background(Theme.surfacePrimary)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    applyThemeToAllWindows()
                    setupDistributedNotificationListener()
                    applyAppBehaviorSettings()
                }
                .onChange(of: themeMode) { _, _ in
                    applyThemeToAllWindows()
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)

        // Menu Bar
        MenuBarExtra("Fetchora", systemImage: "arrow.down.circle.fill", isInserted: $showMenuBar) {
            MenuBarView()
                .id(themeMode)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(colorScheme)
                .onChange(of: themeMode) { _, _ in
                    applyThemeToAllWindows()
                }
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .id(themeMode)
                .frame(width: 500, height: 600)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    applyThemeToAllWindows()
                }
                .onChange(of: themeMode) { _, _ in
                    applyThemeToAllWindows()
                }
        }
    }

    private func setupDistributedNotificationListener() {
        // Listen for download requests from Safari Extension via DistributedNotificationCenter
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.adilemre.SwiftDownloader.newDownload"),
            object: nil,
            queue: .main
        ) { notification in
            // URL and fileName are encoded in the object parameter
            // (userInfo is stripped by App Sandbox)
            guard let payload = notification.object as? String else { return }

            let parts = payload.components(separatedBy: "|||SPLIT|||")
            guard let urlString = parts.first, !urlString.isEmpty else { return }

            let fileName: String
            if parts.count > 1 && !parts[1].isEmpty {
                fileName = parts[1]
            } else {
                fileName = URL(string: urlString)?.lastPathComponent ?? "download"
            }

            addDownload(urlString: urlString, fileName: fileName)
        }
    }

    private func addDownload(urlString: String, fileName: String) {
        guard let url = URL(string: urlString) else { return }

        let destination = FileOrganizer.shared.destinationURL(for: fileName)
        let category = FileCategory.from(extension: url.fileExtensionLowercased)

        let item = DownloadItem(
            url: urlString,
            fileName: fileName,
            destinationPath: destination.path,
            category: category
        )

        let context = sharedModelContainer.mainContext
        context.insert(item)
        try? context.save()

        downloadManager.startDownload(item: item)
    }

    private func applyThemeToAllWindows() {
        let appearance = nsAppearance
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    private func applyAppBehaviorSettings() {
        // Hide from dock
        if UserDefaults.standard.bool(forKey: Constants.Keys.hideFromDock) {
            NSApp.setActivationPolicy(.accessory)
        }

        // Start minimized — close the window, keep menu bar
        if UserDefaults.standard.bool(forKey: Constants.Keys.startMinimized) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.first?.close()
            }
        }
    }
}
