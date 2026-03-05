import Foundation
import Combine
import AppKit

struct ActiveDownloadInfo {
    let task: URLSessionDownloadTask?
    let speedTracker: SpeedTracker
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
}

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [UUID: ActiveDownloadInfo] = [:]
    @Published var speeds: [UUID: Double] = [:]
    @Published var etas: [UUID: TimeInterval] = [:]
    @Published var totalSpeed: Double = 0

    private var session: URLSession!
    private var pendingQueue: [DownloadItem] = []
    private var downloadToItem: [Int: UUID] = [:]
    private var lastUIUpdateTime: [UUID: CFAbsoluteTime] = [:]
    private var retryAttempts: [UUID: Int] = [:]

    var maxConcurrentDownloads: Int {
        get { UserDefaults.standard.integer(forKey: Constants.Keys.maxConcurrentDownloads).clamped(to: 1...10) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.maxConcurrentDownloads) }
    }

    var speedLimitBytesPerSecond: Double {
        let mbps = UserDefaults.standard.double(forKey: Constants.Keys.speedLimitMBps)
        return mbps > 0 ? mbps * 1024 * 1024 : 0
    }

    private override init() {
        super.init()
        session = createSession()

        // Rebuild session when proxy settings change
        let proxyKeys = [Constants.Keys.proxyEnabled, Constants.Keys.proxyType,
                         Constants.Keys.proxyHost, Constants.Keys.proxyPort,
                         Constants.Keys.proxyUsername, Constants.Keys.proxyPassword]
        for key in proxyKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
        }

        UserDefaults.standard.register(defaults: [
            Constants.Keys.maxConcurrentDownloads: Constants.defaultMaxConcurrentDownloads,
            Constants.Keys.soundEnabled: true,
            Constants.Keys.notificationsEnabled: true,
            Constants.Keys.autoRetryEnabled: true,
            Constants.Keys.autoRetryCount: 3
        ])

        // Initialize notification service
        _ = NotificationService.shared
    }

    private func createSession() -> URLSession {
        let config = ProxySettings.configuredSessionConfiguration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 24
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            guard self.activeDownloads.isEmpty else { return }
            self.session = self.createSession()
        }
    }

    // MARK: - Public API

    func startDownload(item: DownloadItem) {
        guard let url = URL(string: item.url) else {
            item.status = .failed
            item.errorMessage = "Invalid URL"
            return
        }

        if activeDownloads.count >= maxConcurrentDownloads {
            item.status = .waiting
            pendingQueue.append(item)
            return
        }

        beginDownload(item: item, url: url)
    }

    func pauseDownload(item: DownloadItem) {
        guard activeDownloads[item.id] != nil else { return }

        let wasSegmented = SegmentedDownloadManager.shared.isSegmented(item.id)

        if wasSegmented {
            // Pause segmented download — preserves completed segment temp files
            _ = SegmentedDownloadManager.shared.pauseSegmented(itemId: item.id)
            item.status = .paused
            item.resumeData = nil
            activeDownloads.removeValue(forKey: item.id)
            speeds.removeValue(forKey: item.id)
            etas.removeValue(forKey: item.id)
            lastUIUpdateTime.removeValue(forKey: item.id)
            updateTotalSpeed()
            if activeDownloads.isEmpty {
                NSApp.dockTile.badgeLabel = nil
            }
            processQueue()
        } else if let task = activeDownloads[item.id]?.task {
            // Normal download — get resume data from the real task
            task.cancel(byProducingResumeData: { [weak self] resumeData in
                Task { @MainActor in
                    item.resumeData = resumeData
                    item.status = .paused
                    self?.activeDownloads.removeValue(forKey: item.id)
                    self?.speeds.removeValue(forKey: item.id)
                    self?.etas.removeValue(forKey: item.id)
                    self?.lastUIUpdateTime.removeValue(forKey: item.id)
                    self?.updateTotalSpeed()
                    if self?.activeDownloads.isEmpty == true {
                        NSApp.dockTile.badgeLabel = nil
                    }
                    self?.processQueue()
                }
            })
        }
    }

    func resumeDownload(item: DownloadItem) {
        if activeDownloads.count >= maxConcurrentDownloads {
            item.status = .waiting
            pendingQueue.insert(item, at: 0)
            return
        }

        if let resumeData = item.resumeData {
            // Normal download resume with URLSession resume data
            let task = session.downloadTask(withResumeData: resumeData)
            let tracker = SpeedTracker()
            activeDownloads[item.id] = ActiveDownloadInfo(task: task, speedTracker: tracker, downloadedBytes: item.downloadedBytes, totalBytes: item.totalBytes)
            downloadToItem[task.taskIdentifier] = item.id
            item.status = .downloading
            item.resumeData = nil
            task.resume()
        } else if SegmentedDownloadManager.shared.hasPausedSegments(item.id) {
            // Resume paused segmented download — tasks are suspended, just resume them
            let tracker = SpeedTracker()
            activeDownloads[item.id] = ActiveDownloadInfo(task: nil, speedTracker: tracker, downloadedBytes: item.downloadedBytes, totalBytes: item.totalBytes)
            item.status = .downloading
            _ = SegmentedDownloadManager.shared.resumeSegmented(itemId: item.id)
        } else if let url = URL(string: item.url) {
            beginDownload(item: item, url: url)
        }
    }

    func cancelDownload(item: DownloadItem) {
        SegmentedDownloadManager.shared.cancelSegmented(itemId: item.id)
        if let info = activeDownloads[item.id] {
            info.task?.cancel()
            activeDownloads.removeValue(forKey: item.id)
            speeds.removeValue(forKey: item.id)
            etas.removeValue(forKey: item.id)
            lastUIUpdateTime.removeValue(forKey: item.id)
            updateTotalSpeed()
        }
        pendingQueue.removeAll { $0.id == item.id }
        item.status = .cancelled
        item.resumeData = nil
        if activeDownloads.isEmpty {
            NSApp.dockTile.badgeLabel = nil
        }
        processQueue()
    }

    func retryDownload(item: DownloadItem) {
        item.status = .waiting
        item.downloadedBytes = 0
        item.resumeData = nil
        item.errorMessage = nil
        startDownload(item: item)
    }

    func pauseAll() {
        let items = Array(activeDownloads.keys)
        for id in items {
            if SegmentedDownloadManager.shared.isSegmented(id) {
                _ = SegmentedDownloadManager.shared.pauseSegmented(itemId: id)
            } else {
                activeDownloads[id]?.task?.cancel(byProducingResumeData: { _ in })
            }
            activeDownloads.removeValue(forKey: id)
        }
        speeds.removeAll()
        etas.removeAll()
        lastUIUpdateTime.removeAll()
        updateTotalSpeed()
        NSApp.dockTile.badgeLabel = nil
    }

    func resumeAll(items: [DownloadItem]) {
        for item in items where item.status == .paused {
            resumeDownload(item: item)
        }
    }

    // MARK: - Private

    private func beginDownload(item: DownloadItem, url: URL) {
        item.status = .downloading

        let itemId = item.id
        let tracker = SpeedTracker()

        // Try segmented download first
        SegmentedDownloadManager.shared.startSegmentedDownload(
            itemId: itemId,
            url: url,
            fileName: item.fileName,
            onProgress: { [weak self] downloaded, total in
                guard let self = self else { return }
                let now = CFAbsoluteTimeGetCurrent()
                let lastUpdate = self.lastUIUpdateTime[itemId] ?? 0
                guard now - lastUpdate >= 0.4 else { return }
                self.lastUIUpdateTime[itemId] = now

                if var info = self.activeDownloads[itemId] {
                    info.downloadedBytes = downloaded
                    info.totalBytes = total
                    info.speedTracker.addSample(totalBytes: downloaded)
                    self.activeDownloads[itemId] = info
                    self.speeds[itemId] = info.speedTracker.currentSpeed
                    self.etas[itemId] = info.speedTracker.estimatedTimeRemaining(
                        totalBytes: total, downloadedBytes: downloaded
                    )
                    self.updateTotalSpeed()
                }

                if let item = self.findItem?(itemId) {
                    item.downloadedBytes = downloaded
                    item.totalBytes = total
                }
                self.updateDockBadge()
            },
            onComplete: { [weak self] resultURL in
                guard let self = self, let item = self.findItem?(itemId) else { return }
                item.destinationPath = resultURL.path
                item.status = .completed
                item.dateCompleted = Date()
                item.downloadedBytes = item.totalBytes
                self.retryAttempts.removeValue(forKey: itemId)

                if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                    NotificationService.shared.showDownloadComplete(fileName: item.fileName, path: resultURL.path)
                }
                NotificationService.shared.playCompletionSound()
                NSApp.dockTile.badgeLabel = nil
                self.performCompletionAction(for: item)

                self.activeDownloads.removeValue(forKey: itemId)
                self.speeds.removeValue(forKey: itemId)
                self.etas.removeValue(forKey: itemId)
                self.lastUIUpdateTime.removeValue(forKey: itemId)
                self.updateTotalSpeed()
                self.processQueue()
            },
            onError: { [weak self] error in
                guard let self = self else { return }

                // Fallback: server doesn't support Range → use normal download
                if (error as NSError).localizedDescription == "USE_NORMAL_DOWNLOAD" {
                    self.beginNormalDownload(item: self.findItem?(itemId) ?? item, url: url, tracker: tracker)
                    return
                }

                if let item = self.findItem?(itemId) {
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                    self.handleAutoRetry(item: item)
                }
                self.activeDownloads.removeValue(forKey: itemId)
                self.speeds.removeValue(forKey: itemId)
                self.etas.removeValue(forKey: itemId)
                self.lastUIUpdateTime.removeValue(forKey: itemId)
                self.updateTotalSpeed()
                self.processQueue()
            }
        )

        // Track segmented download without creating a real URLSessionDownloadTask
        activeDownloads[itemId] = ActiveDownloadInfo(task: nil, speedTracker: tracker)
    }

    /// Normal single-connection download (fallback)
    private func beginNormalDownload(item: DownloadItem, url: URL, tracker: SpeedTracker) {
        var request = URLRequest(url: url)
        request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        activeDownloads[item.id] = ActiveDownloadInfo(task: task, speedTracker: tracker)
        downloadToItem[task.taskIdentifier] = item.id
        item.status = .downloading
        task.resume()
    }

    private func processQueue() {
        while activeDownloads.count < maxConcurrentDownloads, let next = pendingQueue.first {
            pendingQueue.removeFirst()
            if let url = URL(string: next.url) {
                beginDownload(item: next, url: url)
            }
        }
    }

    private func updateTotalSpeed() {
        totalSpeed = speeds.values.reduce(0, +)
    }

    // MARK: - Item Lookup

    // Callback-based item resolution. The app sets this closure so the manager can find items.
    var findItem: ((UUID) -> DownloadItem?)? = nil
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        let now = CFAbsoluteTimeGetCurrent()

        Task { @MainActor in
            guard let itemId = downloadToItem[taskId],
                  var info = activeDownloads[itemId] else { return }

            info.downloadedBytes = totalBytesWritten
            info.totalBytes = totalBytesExpectedToWrite
            info.speedTracker.addSample(totalBytes: totalBytesWritten)
            activeDownloads[itemId] = info

            // Throttle UI updates to ~2x per second to prevent flickering
            let lastUpdate = lastUIUpdateTime[itemId] ?? 0
            guard now - lastUpdate >= 0.5 else { return }
            lastUIUpdateTime[itemId] = now

            let speed = info.speedTracker.currentSpeed
            speeds[itemId] = speed
            etas[itemId] = info.speedTracker.estimatedTimeRemaining(
                totalBytes: totalBytesExpectedToWrite,
                downloadedBytes: totalBytesWritten
            )
            updateTotalSpeed()

            if let item = findItem?(itemId) {
                item.downloadedBytes = totalBytesWritten
                item.totalBytes = totalBytesExpectedToWrite
            }

            // Dock badge progress
            updateDockBadge()
        }
    }

    @MainActor
    private func updateDockBadge() {
        guard !activeDownloads.isEmpty else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let totalDown = activeDownloads.values.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        let totalExp = activeDownloads.values.reduce(Int64(0)) { $0 + $1.totalBytes }
        if totalExp > 0 {
            let pct = Int(Double(totalDown) / Double(totalExp) * 100)
            NSApp.dockTile.badgeLabel = "\(pct)%"
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier

        // Capture suggested filename from server response
        let suggestedName = downloadTask.response?.suggestedFilename

        // MUST move file synchronously — URLSession deletes tmp file after this method returns
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let safeCopy = tempDir.appendingPathComponent(UUID().uuidString + "_" + (location.lastPathComponent))

        var moveResult: Result<URL, Error>
        do {
            try fileManager.moveItem(at: location, to: safeCopy)
            moveResult = .success(safeCopy)
        } catch {
            moveResult = .failure(error)
        }

        Task { @MainActor in
            guard let itemId = self.downloadToItem[taskId],
                  let item = self.findItem?(itemId) else { return }

            // Update fileName from server suggestion if current name lacks an extension
            if let suggested = suggestedName,
               suggested != "Unknown",
               suggested.contains(".") {
                let currentExt = URL(fileURLWithPath: item.fileName).pathExtension
                if currentExt.isEmpty {
                    item.fileName = suggested
                    item.category = FileCategory.from(extension: URL(fileURLWithPath: suggested).pathExtension.lowercased())
                }
            }

            switch moveResult {
            case .success(let safePath):
                let organizer = FileOrganizer.shared
                let destination = organizer.destinationURL(for: item.fileName)

                let parentDir = destination.deletingLastPathComponent()
                try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                do {
                    try fileManager.moveItem(at: safePath, to: destination)
                    item.destinationPath = destination.path
                    item.status = .completed
                    item.dateCompleted = Date()
                    item.downloadedBytes = item.totalBytes
                    self.retryAttempts.removeValue(forKey: itemId)

                    // Notification + Sound
                    if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                        NotificationService.shared.showDownloadComplete(fileName: item.fileName, path: destination.path)
                    }
                    NotificationService.shared.playCompletionSound()

                    // Dock badge progress
                    NSApp.dockTile.badgeLabel = nil

                    // Post-download action
                    self.performCompletionAction(for: item)
                } catch {
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                    try? fileManager.removeItem(at: safePath)
                }

            case .failure(let error):
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }

            self.activeDownloads.removeValue(forKey: itemId)
            self.downloadToItem.removeValue(forKey: taskId)
            self.speeds.removeValue(forKey: itemId)
            self.etas.removeValue(forKey: itemId)
            self.lastUIUpdateTime.removeValue(forKey: itemId)
            self.updateTotalSpeed()

            // Auto-retry on failure
            if item.status == .failed {
                self.handleAutoRetry(item: item)
            }

            self.processQueue()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as? NSError else { return }

        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }

        let taskId = task.taskIdentifier

        Task { @MainActor in
            guard let itemId = downloadToItem[taskId],
                  let item = findItem?(itemId) else { return }

            item.status = .failed
            item.errorMessage = error.localizedDescription

            activeDownloads.removeValue(forKey: itemId)
            downloadToItem.removeValue(forKey: taskId)
            speeds.removeValue(forKey: itemId)
            etas.removeValue(forKey: itemId)
            lastUIUpdateTime.removeValue(forKey: itemId)
            updateTotalSpeed()

            handleAutoRetry(item: item)
            processQueue()
        }
    }

    // MARK: - Auto Retry

    @MainActor
    private func handleAutoRetry(item: DownloadItem) {
        guard UserDefaults.standard.bool(forKey: Constants.Keys.autoRetryEnabled) else {
            if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                NotificationService.shared.showDownloadFailed(fileName: item.fileName, error: item.errorMessage ?? "Unknown")
            }
            return
        }

        let maxRetries = UserDefaults.standard.integer(forKey: Constants.Keys.autoRetryCount)
        let attempts = retryAttempts[item.id, default: 0]

        if attempts < maxRetries {
            retryAttempts[item.id] = attempts + 1
            // Delay retry by 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.retryDownload(item: item)
            }
        } else {
            retryAttempts.removeValue(forKey: item.id)
            if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                NotificationService.shared.showDownloadFailed(fileName: item.fileName, error: "Failed after \(maxRetries) retries")
            }
        }
    }

    // MARK: - Completion Action

    @MainActor
    private func performCompletionAction(for item: DownloadItem) {
        let action = UserDefaults.standard.string(forKey: Constants.Keys.completionAction) ?? "none"
        let fileURL = URL(fileURLWithPath: item.destinationPath)
        switch action {
        case "openFile":
            NSWorkspace.shared.open(fileURL)
        case "openFolder":
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        default:
            break
        }
    }
}

// MARK: - Int Extension
private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        if self < range.lowerBound {
            return self == 0 ? Constants.defaultMaxConcurrentDownloads : range.lowerBound
        }
        return Swift.min(self, range.upperBound)
    }
}
