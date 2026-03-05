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

        // Start with the provided fileName; resolve a better name asynchronously
        let resolvedFileName = fileName
        let destination = FileOrganizer.shared.destinationURL(for: resolvedFileName)
        let category = FileCategory.from(extension: url.fileExtensionLowercased)

        let item = DownloadItem(
            url: urlString,
            fileName: resolvedFileName,
            destinationPath: destination.path,
            category: category
        )

        let context = sharedModelContainer.mainContext
        context.insert(item)
        try? context.save()

        // Resolve the real filename from server (Content-Disposition / Content-Type)
        Task {
            let betterName = await Self.resolveFileName(url: url, fallback: resolvedFileName)
            if betterName != resolvedFileName {
                await MainActor.run {
                    item.fileName = betterName
                    item.category = FileCategory.from(extension: URL(fileURLWithPath: betterName).pathExtension.lowercased())
                    let newDest = FileOrganizer.shared.destinationURL(for: betterName)
                    item.destinationPath = newDest.path
                    try? context.save()
                }
            }
            await MainActor.run {
                downloadManager.startDownload(item: item)
            }
        }
    }

    /// Resolves a proper file name by sending a HEAD request and inspecting
    /// Content-Disposition and Content-Type headers.
    private static func resolveFileName(url: URL, fallback: String) async -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return fallback }

            // Determine the correct extension from Content-Type
            let mimeExt: String? = {
                if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first {
                    let mime = String(contentType).trimmingCharacters(in: .whitespaces).lowercased()
                    return Self.extensionFromMIME(mime)
                }
                return nil
            }()

            // 1) Try suggestedFilename from URLResponse (parses Content-Disposition)
            if let suggested = response.suggestedFilename,
               suggested != "Unknown",
               suggested.contains(".") {
                // Verify the extension matches Content-Type; fix if mismatched
                // (e.g. Apple sometimes returns .txt for text/html)
                if let correctExt = mimeExt {
                    let suggestedExt = URL(fileURLWithPath: suggested).pathExtension.lowercased()
                    if suggestedExt != correctExt {
                        let nameWithoutExt = (suggested as NSString).deletingPathExtension
                        return nameWithoutExt + "." + correctExt
                    }
                }
                return suggested
            }

            // 2) Fallback has extension already → keep it
            if fallback.contains(".") && URL(fileURLWithPath: fallback).pathExtension.count > 0 {
                return fallback
            }

            // 3) Derive extension from Content-Type
            if let ext = mimeExt {
                return fallback + "." + ext
            }
        } catch {}
        return fallback
    }

    private static func extensionFromMIME(_ mime: String) -> String? {
        let map: [String: String] = [
            "text/html": "html",
            "text/plain": "txt",
            "text/css": "css",
            "text/csv": "csv",
            "text/xml": "xml",
            "application/json": "json",
            "application/xml": "xml",
            "application/pdf": "pdf",
            "application/zip": "zip",
            "application/gzip": "gz",
            "application/x-tar": "tar",
            "application/x-7z-compressed": "7z",
            "application/x-rar-compressed": "rar",
            "application/x-bzip2": "bz2",
            "application/x-xz": "xz",
            "application/x-apple-diskimage": "dmg",
            "application/msword": "doc",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
            "application/vnd.ms-excel": "xls",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
            "application/vnd.ms-powerpoint": "ppt",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
            "application/x-bittorrent": "torrent",
            "application/javascript": "js",
            "video/mp4": "mp4",
            "video/x-matroska": "mkv",
            "video/x-msvideo": "avi",
            "video/quicktime": "mov",
            "video/webm": "webm",
            "video/x-flv": "flv",
            "audio/mpeg": "mp3",
            "audio/wav": "wav",
            "audio/flac": "flac",
            "audio/aac": "aac",
            "audio/ogg": "ogg",
            "audio/mp4": "m4a",
            "image/jpeg": "jpg",
            "image/png": "png",
            "image/gif": "gif",
            "image/svg+xml": "svg",
            "image/webp": "webp",
            "image/bmp": "bmp",
            "image/tiff": "tiff",
        ]
        return map[mime] ?? nil
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
