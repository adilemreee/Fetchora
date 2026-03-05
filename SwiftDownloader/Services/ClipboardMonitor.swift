import Foundation
import AppKit

/// Monitors the system clipboard for copied URLs and offers to download them.
@MainActor
class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published var detectedURL: String?
    @Published var showURLPrompt = false

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var ignoredURLs: Set<String> = []

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.Keys.clipboardMonitoring) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.clipboardMonitoring) }
    }

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startMonitoring() {
        guard isEnabled else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func ignoreCurrentURL() {
        if let url = detectedURL {
            ignoredURLs.insert(url)
        }
        detectedURL = nil
        showURLPrompt = false
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = pasteboard.string(forType: .string),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil,
              !ignoredURLs.contains(text) else { return }

        // Check if it looks like a downloadable file
        let ext = url.pathExtension.lowercased()
        let isDownloadable = !ext.isEmpty && Constants.downloadableExtensions.contains(ext)

        if isDownloadable {
            detectedURL = text
            showURLPrompt = true
        }
    }
}
