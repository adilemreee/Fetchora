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

    static func shouldRecoverOnLaunch(status: DownloadStatus) -> Bool {
        DownloadRecoveryPlanner.shouldRecoverOnLaunch(status: status)
    }

    @Published var activeDownloads: [UUID: ActiveDownloadInfo] = [:]
    @Published var speeds: [UUID: Double] = [:]
    @Published var etas: [UUID: TimeInterval] = [:]
    @Published var totalSpeed: Double = 0

    private var session: URLSession!
    private var pendingQueue: [DownloadItem] = []
    private var downloadToItem: [Int: UUID] = [:]
    private var lastUIUpdateTime: [UUID: CFAbsoluteTime] = [:]
    private var retryAttempts: [UUID: Int] = [:]
    private var throttleTimer: Timer?
    private let trafficLimiter = DownloadTrafficLimiter()

    var maxConcurrentDownloads: Int {
        get { UserDefaults.standard.integer(forKey: Constants.Keys.maxConcurrentDownloads).clamped(to: 1...10) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.maxConcurrentDownloads) }
    }

    var speedLimitBytesPerSecond: Double {
        let preset = UserDefaults.standard.string(forKey: Constants.Keys.speedLimitPreset) ?? "high"
        switch preset {
        case "low": return 512 * 1024              // 512 KB/s
        case "medium": return 2 * 1024 * 1024      // 2 MB/s
        case "custom":
            let kbps = UserDefaults.standard.double(forKey: Constants.Keys.speedLimitCustomKBps)
            return kbps > 0 ? kbps * 1024 : 0
        default: return 0 // "high" = unlimited
        }
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

        // Start speed throttle timer
        startThrottleTimer()
    }

    // MARK: - Speed Throttling

    private func startThrottleTimer() {
        throttleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enforceSpeedLimit()
            }
        }
    }

    private var throttledTaskIds: Set<UUID> = []

    private func enforceSpeedLimit() {
        let decision = trafficLimiter.evaluate(
            limitBytesPerSecond: speedLimitBytesPerSecond,
            totalDownloadedBytes: activeDownloads.values.reduce(Int64(0)) { $0 + $1.downloadedBytes },
            activeDownloadCount: activeDownloads.count
        )

        switch decision {
        case .none:
            break
        case .suspendAll:
            suspendAllActive()
        case .resumeAll:
            resumeAllThrottled()
        case .reset:
            if !throttledTaskIds.isEmpty {
                resumeAllThrottled()
            }
        }
    }

    func speedLimitConfigurationDidChange() {
        if !throttledTaskIds.isEmpty {
            resumeAllThrottled()
        }

        for id in activeDownloads.keys {
            activeDownloads[id]?.speedTracker.reset()
            speeds[id] = 0
            if SegmentedDownloadManager.shared.isSegmented(id) || SegmentedDownloadManager.shared.hasPausedSegments(id) {
                SegmentedDownloadManager.shared.setBandwidthConstrained(speedLimitBytesPerSecond > 0, for: id)
            }
        }

        updateTotalSpeed()
        trafficLimiter.reset()
    }

    func refreshScheduling() {
        synchronizePendingQueue()
        processQueue()
    }

    private func suspendAllActive() {
        for (id, info) in activeDownloads {
            if let task = info.task {
                task.suspend()
            } else if SegmentedDownloadManager.shared.isSegmented(id) {
                SegmentedDownloadManager.shared.throttleSuspend(itemId: id)
            }
            throttledTaskIds.insert(id)
        }
    }

    private func resumeAllThrottled() {
        for id in throttledTaskIds {
            if let task = activeDownloads[id]?.task {
                task.resume()
            } else if SegmentedDownloadManager.shared.isSegmented(id) {
                SegmentedDownloadManager.shared.throttleResume(itemId: id)
            }
        }
        throttledTaskIds.removeAll()
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

        pendingQueue.removeAll { $0.id == item.id }

        if activeDownloads.count >= maxConcurrentDownloads {
            item.status = .waiting
            enqueuePending(item)
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
            let itemId = item.id
            task.cancel(byProducingResumeData: { [weak self] resumeData in
                Task { @MainActor in
                    if let item = self?.findItem?(itemId) {
                        item.resumeData = resumeData
                        item.status = .paused
                    }
                    self?.activeDownloads.removeValue(forKey: itemId)
                    self?.speeds.removeValue(forKey: itemId)
                    self?.etas.removeValue(forKey: itemId)
                    self?.lastUIUpdateTime.removeValue(forKey: itemId)
                    self?.updateTotalSpeed()
                    if self?.activeDownloads.isEmpty == true {
                        NSApp.dockTile.badgeLabel = nil
                    }
                    self?.processQueue()
                }
            })
        }
    }

    /// Force-start a waiting download, bypassing the concurrent limit.
    func forceStartDownload(item: DownloadItem) {
        // Remove from pending queue if present
        pendingQueue.removeAll { $0.id == item.id }

        guard let url = URL(string: item.url) else {
            item.status = .failed
            item.errorMessage = "Invalid URL"
            return
        }
        beginDownload(item: item, url: url)
    }

    func resumeDownload(item: DownloadItem, force: Bool = false) {
        if !force && activeDownloads.count >= maxConcurrentDownloads {
            item.status = .waiting
            enqueuePending(item)
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
            SegmentedDownloadManager.shared.setBandwidthConstrained(speedLimitBytesPerSecond > 0, for: item.id)
            _ = SegmentedDownloadManager.shared.resumeSegmented(itemId: item.id)
        } else if let url = URL(string: item.url) {
            beginDownload(item: item, url: url)
        }
    }

    func cancelDownload(item: DownloadItem) {
        cleanupRuntimeState(for: item, markCancelled: true, deleteCompletedFile: false)
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
        let ids = Array(activeDownloads.keys)
        for id in ids {
            if let item = findItem?(id) {
                pauseDownload(item: item)
            } else {
                // Fallback: clean up orphaned tracking
                if SegmentedDownloadManager.shared.isSegmented(id) {
                    _ = SegmentedDownloadManager.shared.pauseSegmented(itemId: id)
                } else {
                    activeDownloads[id]?.task?.cancel(byProducingResumeData: { _ in })
                }
                activeDownloads.removeValue(forKey: id)
                speeds.removeValue(forKey: id)
                etas.removeValue(forKey: id)
                lastUIUpdateTime.removeValue(forKey: id)
            }
        }
        updateTotalSpeed()
        NSApp.dockTile.badgeLabel = nil
    }

    func removeFromPendingQueue(itemId: UUID) {
        pendingQueue.removeAll { $0.id == itemId }
    }

    func prepareForRemoval(item: DownloadItem, deleteCompletedFile: Bool = false) {
        cleanupRuntimeState(for: item, markCancelled: false, deleteCompletedFile: deleteCompletedFile)
        processQueue()
    }

    func recoverInterruptedDownloads(items: [DownloadItem]) {
        cleanupStalePlaceholders(for: items)

        let recoverableItems = DownloadRecoveryPlanner.itemsNeedingRecovery(from: items)
            .sorted { $0.dateAdded < $1.dateAdded }

        for item in recoverableItems {
            item.errorMessage = nil

            if item.status == .waiting {
                startDownload(item: item)
            } else {
                resumeDownload(item: item)
            }
        }
    }

    func resumeAll(items: [DownloadItem]) {
        for item in items where item.status == .paused {
            resumeDownload(item: item)
        }
    }

    // MARK: - Private

    /// Tracks the .fetchoradownload placeholder path for each active download
    private var tempPlaceholders: [UUID: URL] = [:]

    private func beginDownload(item: DownloadItem, url: URL) {
        item.errorMessage = nil
        item.dateCompleted = nil
        item.status = .downloading

        let itemId = item.id
        let tracker = SpeedTracker()

        // Create .fetchoradownload placeholder in the download directory
        createTempPlaceholder(for: item)

        if speedLimitBytesPerSecond > 0 {
            beginNormalDownload(item: item, url: url, tracker: tracker)
            return
        }

        // Try segmented download first
        SegmentedDownloadManager.shared.startSegmentedDownload(
            itemId: itemId,
            url: url,
            fileName: item.fileName,
            destinationURL: URL(fileURLWithPath: item.destinationPath),
            onProgress: { [weak self] downloaded, total in
                guard let self = self else { return }
                // Always update bytes and speed tracker (decoupled from UI throttle)
                guard var info = self.activeDownloads[itemId] else { return }
                info.downloadedBytes = downloaded
                info.totalBytes = total
                info.speedTracker.addSample(totalBytes: downloaded)
                self.activeDownloads[itemId] = info

                // Throttle UI updates to ~2.5x per second
                let now = CFAbsoluteTimeGetCurrent()
                let lastUpdate = self.lastUIUpdateTime[itemId] ?? 0
                guard now - lastUpdate >= 0.4 else { return }
                self.lastUIUpdateTime[itemId] = now

                self.speeds[itemId] = info.speedTracker.currentSpeed
                self.etas[itemId] = info.speedTracker.estimatedTimeRemaining(
                    totalBytes: total, downloadedBytes: downloaded
                )
                self.updateTotalSpeed()

                if let item = self.findItem?(itemId) {
                    item.downloadedBytes = downloaded
                    item.totalBytes = total
                }
                self.updateDockBadge()
            },
            onComplete: { [weak self] resultURL in
                guard let self = self, let item = self.findItem?(itemId) else { return }
                // Ignore if item was paused/cancelled while segments were finishing
                guard item.status == .downloading else { return }

                item.destinationPath = resultURL.path
                item.status = .completed
                item.dateCompleted = Date()
                item.downloadedBytes = item.totalBytes
                self.retryAttempts.removeValue(forKey: itemId)
                self.removeTempPlaceholder(for: itemId, destinationPath: item.destinationPath)

                if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                    NotificationService.shared.showDownloadComplete(fileName: item.fileName, path: resultURL.path)
                }
                NotificationService.shared.playCompletionSound()
                NSApp.dockTile.badgeLabel = nil
                self.performCompletionAction(for: item)

                NotificationCenter.default.post(name: Constants.Notifications.downloadCompleted,
                                                object: nil,
                                                userInfo: ["itemId": itemId])

                self.activeDownloads.removeValue(forKey: itemId)
                self.speeds.removeValue(forKey: itemId)
                self.etas.removeValue(forKey: itemId)
                self.lastUIUpdateTime.removeValue(forKey: itemId)
                self.updateTotalSpeed()
                self.processQueue()
            },
            onError: { [weak self] error in
                guard let self = self else { return }

                // Ignore errors for paused/cancelled items (suspended tasks may fire errors)
                if let currentItem = self.findItem?(itemId),
                   currentItem.status == .paused || currentItem.status == .cancelled {
                    return
                }

                // Fallback: server doesn't support Range → use normal download
                if (error as NSError).localizedDescription == "USE_NORMAL_DOWNLOAD" {
                    if let currentItem = self.findItem?(itemId), currentItem.status == .downloading {
                        self.beginNormalDownload(item: currentItem, url: url, tracker: tracker)
                    }
                    return
                }

                if let item = self.findItem?(itemId) {
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                    self.removeTempPlaceholder(for: itemId, destinationPath: item.destinationPath)
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
        synchronizePendingQueue()
        pendingQueue = DownloadQueuePlanner.orderedPendingQueue(pendingQueue)

        if applyPriorityPreemptionIfNeeded() {
            return
        }

        let itemsToStart = DownloadQueuePlanner.nextItemsToStart(
            activeCount: activeDownloads.count,
            maxConcurrent: maxConcurrentDownloads,
            pendingQueue: pendingQueue
        )

        for next in itemsToStart {
            pendingQueue.removeAll { $0.id == next.id }
            if let url = URL(string: next.url) {
                activateQueuedItem(next, url: url)
            }
        }

        _ = applyPriorityPreemptionIfNeeded()
    }

    private func enqueuePending(_ item: DownloadItem) {
        pendingQueue.removeAll { $0.id == item.id }
        pendingQueue.append(item)
        pendingQueue = DownloadQueuePlanner.orderedPendingQueue(pendingQueue)
    }

    private func synchronizePendingQueue() {
        guard let allItemsProvider else {
            pendingQueue = DownloadQueuePlanner.orderedPendingQueue(pendingQueue)
            return
        }

        let trackedIds = Set(activeDownloads.keys)
        let waitingItems = allItemsProvider().filter { $0.status == .waiting && !trackedIds.contains($0.id) }
        pendingQueue = DownloadQueuePlanner.mergedPendingQueue(
            trackedQueue: pendingQueue,
            allWaitingItems: waitingItems
        )
    }

    private func activateQueuedItem(_ item: DownloadItem, url: URL) {
        if item.resumeData != nil || SegmentedDownloadManager.shared.hasPausedSegments(item.id) {
            resumeDownload(item: item, force: true)
        } else {
            beginDownload(item: item, url: url)
        }
    }

    private func applyPriorityPreemptionIfNeeded() -> Bool {
        guard let findItem else { return false }

        let activeItems = activeDownloads.keys.compactMap(findItem)
        guard let decision = DownloadQueuePlanner.preemptionDecision(
            activeItems: activeItems,
            pendingQueue: pendingQueue,
            maxConcurrent: maxConcurrentDownloads
        ) else {
            return false
        }

        yieldDownloadSlot(for: decision.activeItemToYield)
        return true
    }

    private func yieldDownloadSlot(for item: DownloadItem) {
        pendingQueue.removeAll { $0.id == item.id }

        if SegmentedDownloadManager.shared.isSegmented(item.id) {
            _ = SegmentedDownloadManager.shared.pauseSegmented(itemId: item.id)
            item.status = .waiting
            activeDownloads.removeValue(forKey: item.id)
            speeds.removeValue(forKey: item.id)
            etas.removeValue(forKey: item.id)
            lastUIUpdateTime.removeValue(forKey: item.id)
            updateTotalSpeed()
            enqueuePending(item)
            processQueue()
            return
        }

        guard let task = activeDownloads[item.id]?.task else { return }
        let itemId = item.id

        task.cancel(byProducingResumeData: { [weak self] resumeData in
            Task { @MainActor in
                guard let self, let item = self.findItem?(itemId) else { return }
                item.resumeData = resumeData
                item.status = .waiting
                self.activeDownloads.removeValue(forKey: itemId)
                self.speeds.removeValue(forKey: itemId)
                self.etas.removeValue(forKey: itemId)
                self.lastUIUpdateTime.removeValue(forKey: itemId)
                self.updateTotalSpeed()
                self.enqueuePending(item)
                self.processQueue()
            }
        })
    }

    private func updateTotalSpeed() {
        totalSpeed = speeds.values.reduce(0, +)
    }

    // MARK: - Item Lookup

    // Callback-based item resolution. The app sets this closure so the manager can find items.
    var findItem: ((UUID) -> DownloadItem?)? = nil
    var allItemsProvider: (() -> [DownloadItem])? = nil
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

            self.applySuggestedFilenameIfNeeded(suggestedName, to: item)

            switch moveResult {
            case .success(let safePath):
                let destination = URL(fileURLWithPath: item.destinationPath)

                let parentDir = destination.deletingLastPathComponent()
                try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                FileOrganizer.shared.prepareOverwrite(at: destination)

                do {
                    try fileManager.moveItem(at: safePath, to: destination)
                    item.destinationPath = destination.path
                    item.status = .completed
                    item.dateCompleted = Date()
                    item.downloadedBytes = item.totalBytes
                    self.retryAttempts.removeValue(forKey: itemId)
                    self.removeTempPlaceholder(for: itemId, destinationPath: destination.path)

                    // Notification + Sound
                    if UserDefaults.standard.bool(forKey: Constants.Keys.notificationsEnabled) {
                        NotificationService.shared.showDownloadComplete(fileName: item.fileName, path: destination.path)
                    }
                    NotificationService.shared.playCompletionSound()

                    // Dock badge progress
                    NSApp.dockTile.badgeLabel = nil

                    // Post-download action
                    self.performCompletionAction(for: item)

                    NotificationCenter.default.post(name: Constants.Notifications.downloadCompleted,
                                                    object: nil,
                                                    userInfo: ["itemId": itemId])
                } catch {
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                    try? fileManager.removeItem(at: safePath)
                    self.removeTempPlaceholder(for: itemId, destinationPath: destination.path)
                }

            case .failure(let error):
                item.status = .failed
                item.errorMessage = error.localizedDescription
                self.removeTempPlaceholder(for: itemId, destinationPath: item.destinationPath)
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
            removeTempPlaceholder(for: itemId, destinationPath: item.destinationPath)

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
        // Auto-extract archives
        if UserDefaults.standard.bool(forKey: Constants.Keys.autoExtractArchives) {
            let archiveExtensions: Set<String> = ["zip", "tar", "tgz", "gz", "bz2", "xz", "cpio"]
            let ext = URL(fileURLWithPath: item.destinationPath).pathExtension.lowercased()
            if archiveExtensions.contains(ext) {
                extractArchive(at: item.destinationPath)
            }
        }

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

    /// Extract an archive using macOS built-in `ditto` (supports zip, cpio, etc.)
    private func extractArchive(at path: String) {
        let fileURL = URL(fileURLWithPath: path)
        let extractDir = fileURL.deletingPathExtension()

        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        let ext = fileURL.pathExtension.lowercased()

        if ext == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", path, extractDir.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", path, "-C", extractDir.path]
        }

        do {
            try process.run()
        } catch {
            // ditto failed — silently ignore
        }
    }

    // MARK: - Temp Placeholder (.fetchoradownload)

    /// Creates a visible placeholder file (e.g. "movie.mp4.fetchoradownload") in the download directory
    /// so the user can see the download is in progress, similar to FDM's .fdmdownload files.
    private func createTempPlaceholder(for item: DownloadItem) {
        let destination = URL(fileURLWithPath: item.destinationPath)
        let placeholder = FileOrganizer.shared.placeholderURL(for: destination)
        let parentDir = placeholder.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: placeholder.path, contents: nil)
        tempPlaceholders[item.id] = placeholder
    }

    /// Removes the .fetchoradownload placeholder when download completes or is cancelled.
    private func removeTempPlaceholder(for itemId: UUID, destinationPath: String? = nil) {
        if let placeholder = tempPlaceholders.removeValue(forKey: itemId) {
            try? FileManager.default.removeItem(at: placeholder)
        }

        if let destinationPath {
            FileOrganizer.shared.removePlaceholder(for: destinationPath)
        }
    }

    private func applySuggestedFilenameIfNeeded(_ suggestedName: String?, to item: DownloadItem) {
        guard let suggestedName,
              suggestedName != "Unknown",
              suggestedName.contains(".") else { return }

        let currentExt = URL(fileURLWithPath: item.fileName).pathExtension
        guard currentExt.isEmpty else { return }

        item.fileName = suggestedName
        item.category = FileCategory.from(extension: URL(fileURLWithPath: suggestedName).pathExtension.lowercased())

        let destinationDirectory = URL(fileURLWithPath: item.destinationPath).deletingLastPathComponent()
        item.destinationPath = FileOrganizer.shared.destinationURL(
            for: suggestedName,
            overwriteExisting: false,
            preferredDirectory: destinationDirectory
        ).path
    }

    private func cleanupRuntimeState(for item: DownloadItem, markCancelled: Bool, deleteCompletedFile: Bool) {
        SegmentedDownloadManager.shared.cancelSegmented(itemId: item.id)
        SegmentedDownloadManager.shared.cleanupPersistedSegments(itemId: item.id)

        if let info = activeDownloads[item.id] {
            info.task?.cancel()
        }

        activeDownloads.removeValue(forKey: item.id)
        speeds.removeValue(forKey: item.id)
        etas.removeValue(forKey: item.id)
        lastUIUpdateTime.removeValue(forKey: item.id)
        pendingQueue.removeAll { $0.id == item.id }
        downloadToItem = downloadToItem.filter { $0.value != item.id }
        retryAttempts.removeValue(forKey: item.id)
        item.resumeData = nil
        removeTempPlaceholder(for: item.id, destinationPath: item.destinationPath)

        if deleteCompletedFile, item.fileExists {
            try? FileManager.default.removeItem(atPath: item.destinationPath)
        }

        if markCancelled {
            item.status = .cancelled
        }

        if activeDownloads.isEmpty {
            NSApp.dockTile.badgeLabel = nil
        }

        updateTotalSpeed()
    }

    private func cleanupStalePlaceholders(for items: [DownloadItem]) {
        for item in items {
            FileOrganizer.shared.removePlaceholder(for: item.destinationPath)
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
