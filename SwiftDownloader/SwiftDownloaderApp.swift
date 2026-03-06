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
            // If migration fails, try with a fresh store
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [inMemoryConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
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
                    setupDistributedNotificationListenerOnce()
                    applyAppBehaviorSettings()
                }
                .onChange(of: themeMode) { _, _ in
                    applyThemeToAllWindows()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandMenu("Debug") {
                Button("Load Demo Data") {
                    NotificationCenter.default.post(name: Notification.Name("loadDemoData"), object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Clear Demo Data") {
                    NotificationCenter.default.post(name: Notification.Name("clearDemoData"), object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }

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

    private static var didSetupListener = false
    private func setupDistributedNotificationListenerOnce() {
        guard !Self.didSetupListener else { return }
        Self.didSetupListener = true
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

        // Listen for blob download requests from Safari Extension
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.adilemre.SwiftDownloader.blobDownload"),
            object: nil,
            queue: .main
        ) { notification in
            guard let payload = notification.object as? String else { return }

            let parts = payload.components(separatedBy: "|||SPLIT|||")
            guard let tempPath = parts.first, !tempPath.isEmpty else { return }

            let fileName: String
            if parts.count > 1 && !parts[1].isEmpty {
                fileName = parts[1]
            } else {
                fileName = "download"
            }

            completeBlobDownload(tempPath: tempPath, fileName: fileName)
        }

        // Listen for "open app" requests from Safari Extension
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.adilemre.SwiftDownloader.openApp"),
            object: nil,
            queue: .main
        ) { _ in
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
                if window.isMiniaturized { window.deminiaturize(nil) }
            }
        }
    }

    private func addDownload(urlString: String, fileName: String) {
        // Route through ContentView so duplicate detection works
        NotificationCenter.default.post(
            name: Notification.Name("addDownloadURL"),
            object: nil,
            userInfo: ["url": urlString]
        )
    }

    private func completeBlobDownload(tempPath: String, fileName: String) {
        // Route blob download through ContentView for proper record-keeping
        NotificationCenter.default.post(
            name: Notification.Name("completeBlobDownload"),
            object: nil,
            userInfo: ["tempPath": tempPath, "fileName": fileName]
        )
    }

    private func applyThemeToAllWindows() {
        let appearance = nsAppearance
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "fetchora" else { return }

        switch url.host {
        case "download":
            // fetchora://download?url=<encoded_url>
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value {
                addDownload(urlString: urlParam, fileName: URL(string: urlParam)?.lastPathComponent ?? "download")
            }
        case "blob-download":
            // fetchora://blob-download?tempPath=<path>&fileName=<name>
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let tempPath = components.queryItems?.first(where: { $0.name == "tempPath" })?.value,
               let fileName = components.queryItems?.first(where: { $0.name == "fileName" })?.value {
                completeBlobDownload(tempPath: tempPath, fileName: fileName)
            }
        default:
            // fetchora://open or any other — just bring the window to front
            break
        }

        // Always activate the app and show the main window
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
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
