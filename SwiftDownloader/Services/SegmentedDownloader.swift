import Foundation
import AppKit

/// Downloads a file using multiple concurrent URLSessionDataTask instances with HTTP Range headers.
/// Each segment writes data incrementally to a temp file, enabling reliable pause/resume.
/// Segments are merged after completion. Falls back to single connection if Range not supported.
@MainActor
class SegmentedDownloadManager: NSObject, ObservableObject {
    static let shared = SegmentedDownloadManager()

    private var segmentSessions: [UUID: URLSession] = [:]
    private var segmentDelegates: [UUID: SegmentDelegate] = [:]
    private var activeSegmentedDownloads: Set<UUID> = []
    private var bandwidthConstrainedDownloads: Set<UUID> = []

    // Persist download info for pause/resume
    private var downloadURLs: [UUID: URL] = [:]
    private var downloadFileNames: [UUID: String] = [:]
    private var downloadDestinations: [UUID: URL] = [:]
    private var downloadCallbacks: [UUID: SegmentCallbacks] = [:]

    let segmentCount = 4
    let minFileSize: Int64 = 5 * 1024 * 1024 // 5MB minimum for segmented

    struct SegmentCallbacks {
        let onProgress: @MainActor (Int64, Int64) -> Void
        let onComplete: @MainActor (URL) -> Void
        let onError: @MainActor (Error) -> Void
    }

    /// Check if server supports Range and get file size
    func checkRangeSupport(url: URL) async -> (supportsRange: Bool, contentLength: Int64) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, 0) }
            let length = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
            let accepts = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
            return (accepts && length > 0, length)
        } catch {
            return (false, 0)
        }
    }

    /// Start a segmented download. Returns true if segmented, false if should use normal download.
    func startSegmentedDownload(
        itemId: UUID,
        url: URL,
        fileName: String,
        destinationURL: URL,
        onProgress: @escaping @MainActor (Int64, Int64) -> Void,
        onComplete: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        activeSegmentedDownloads.insert(itemId)
        downloadURLs[itemId] = url
        downloadFileNames[itemId] = fileName
        downloadDestinations[itemId] = destinationURL
        downloadCallbacks[itemId] = SegmentCallbacks(onProgress: onProgress, onComplete: onComplete, onError: onError)

        Task {
            let info = await checkRangeSupport(url: url)

            // If paused/cancelled during HEAD request, bail out
            guard await MainActor.run(body: { activeSegmentedDownloads.contains(itemId) }) else {
                return
            }

            guard info.supportsRange && info.contentLength >= minFileSize else {
                // Not suitable for segmented — caller should use normal download
                await MainActor.run {
                    activeSegmentedDownloads.remove(itemId)
                    downloadURLs.removeValue(forKey: itemId)
                    downloadFileNames.removeValue(forKey: itemId)
                    downloadDestinations.removeValue(forKey: itemId)
                    downloadCallbacks.removeValue(forKey: itemId)
                    onError(NSError(domain: "SegmentedDownload", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "USE_NORMAL_DOWNLOAD"]))
                }
                return
            }

            await MainActor.run {
                // Re-check after await — might have been paused/cancelled
                guard self.activeSegmentedDownloads.contains(itemId) else { return }
                self.performSegmentedDownload(
                    itemId: itemId,
                    url: url,
                    fileName: fileName,
                    destinationURL: destinationURL,
                    totalSize: info.contentLength,
                    onProgress: onProgress,
                    onComplete: onComplete,
                    onError: onError
                )
            }
        }
    }

    func cancelSegmented(itemId: UUID) {
        if let delegate = segmentDelegates[itemId] {
            delegate.cancelAllTasks()
            delegate.cleanupTempFiles()
        }
        segmentSessions[itemId]?.invalidateAndCancel()
        segmentSessions.removeValue(forKey: itemId)
        segmentDelegates.removeValue(forKey: itemId)
        activeSegmentedDownloads.remove(itemId)
        downloadURLs.removeValue(forKey: itemId)
        downloadFileNames.removeValue(forKey: itemId)
        downloadDestinations.removeValue(forKey: itemId)
        downloadCallbacks.removeValue(forKey: itemId)
        bandwidthConstrainedDownloads.remove(itemId)
        cleanupPersistedSegments(itemId: itemId)
    }

    func isSegmented(_ itemId: UUID) -> Bool {
        activeSegmentedDownloads.contains(itemId)
    }

    /// Pause a segmented download by cancelling tasks. Temp files are preserved on disk for resume.
    func pauseSegmented(itemId: UUID) -> Bool {
        if let delegate = segmentDelegates[itemId] {
            delegate.cancelAllTasks()
            // Don't cleanup temp files — they contain downloaded data for resume
        }
        // Invalidate session but keep delegate alive for state
        segmentSessions[itemId]?.invalidateAndCancel()
        segmentSessions.removeValue(forKey: itemId)
        activeSegmentedDownloads.remove(itemId)
        return true
    }

    /// Check if there is a paused segmented download that can be resumed.
    func hasPausedSegments(_ itemId: UUID) -> Bool {
        segmentDelegates[itemId] != nil && !activeSegmentedDownloads.contains(itemId)
    }

    func setBandwidthConstrained(_ isConstrained: Bool, for itemId: UUID) {
        if isConstrained {
            bandwidthConstrainedDownloads.insert(itemId)
        } else {
            bandwidthConstrainedDownloads.remove(itemId)
        }

        segmentDelegates[itemId]?.setPreferredConcurrentSegments(isConstrained ? 1 : segmentCount)
    }

    /// Resume a previously paused segmented download by creating new tasks from where we left off.
    func resumeSegmented(itemId: UUID) -> Bool {
        guard let delegate = segmentDelegates[itemId],
              let url = downloadURLs[itemId],
              !activeSegmentedDownloads.contains(itemId) else { return false }

        activeSegmentedDownloads.insert(itemId)

        // Create a new session
        let config = ProxySettings.configuredSessionConfiguration()
        config.httpMaximumConnectionsPerHost = segmentCount
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 24

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        segmentSessions[itemId] = session
        delegate.setPreferredConcurrentSegments(bandwidthConstrainedDownloads.contains(itemId) ? 1 : segmentCount)

        // Resume by creating new tasks with adjusted Range headers based on temp file sizes
        delegate.resumeWithNewTasks(session: session, url: url)

        return true
    }

    /// Temporarily suspend segment tasks for speed throttling (does NOT change active/paused state).
    func throttleSuspend(itemId: UUID) {
        segmentDelegates[itemId]?.throttleSuspendTasks()
    }

    /// Resume segment tasks after speed throttling (does NOT change active/paused state).
    func throttleResume(itemId: UUID) {
        segmentDelegates[itemId]?.throttleResumeTasks()
    }

    func cleanupPersistedSegments(itemId: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
        for index in 0..<segmentCount {
            let fileURL = tempDir.appendingPathComponent("seg_\(itemId)_\(index).tmp")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Private

    private func performSegmentedDownload(
        itemId: UUID,
        url: URL,
        fileName: String,
        destinationURL: URL,
        totalSize: Int64,
        onProgress: @escaping @MainActor (Int64, Int64) -> Void,
        onComplete: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        let segSize = totalSize / Int64(segmentCount)
        var ranges: [(start: Int64, end: Int64)] = []

        for i in 0..<segmentCount {
            let start = Int64(i) * segSize
            let end = (i == segmentCount - 1) ? (totalSize - 1) : (start + segSize - 1)
            ranges.append((start, end))
        }

        let delegate = SegmentDelegate(
            itemId: itemId,
            segmentCount: segmentCount,
            totalSize: totalSize,
            fileName: fileName,
            destinationURL: destinationURL,
            originalRanges: ranges,
            onProgress: onProgress,
            onComplete: { [weak self] resultURL in
                self?.segmentSessions.removeValue(forKey: itemId)
                self?.segmentDelegates.removeValue(forKey: itemId)
                self?.activeSegmentedDownloads.remove(itemId)
                self?.downloadURLs.removeValue(forKey: itemId)
                self?.downloadFileNames.removeValue(forKey: itemId)
                self?.downloadDestinations.removeValue(forKey: itemId)
                self?.downloadCallbacks.removeValue(forKey: itemId)
                onComplete(resultURL)
            },
            onError: { [weak self] error in
                self?.segmentSessions.removeValue(forKey: itemId)
                self?.segmentDelegates.removeValue(forKey: itemId)
                self?.activeSegmentedDownloads.remove(itemId)
                onError(error)
            }
        )
        delegate.setPreferredConcurrentSegments(bandwidthConstrainedDownloads.contains(itemId) ? 1 : segmentCount)

        let config = ProxySettings.configuredSessionConfiguration()
        config.httpMaximumConnectionsPerHost = segmentCount
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 24

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        segmentDelegates[itemId] = delegate
        segmentSessions[itemId] = session

        // Start all segment downloads
        delegate.startAllTasks(session: session, url: url)
    }
}

// MARK: - Segment Delegate

/// Handles download callbacks for all segments of a single file download.
/// Uses URLSessionDataTask + incremental file writing for reliable pause/resume.
private class SegmentDelegate: NSObject, URLSessionDataDelegate {
    let itemId: UUID
    let segmentCount: Int
    let totalSize: Int64
    let fileName: String
    let destinationURL: URL
    let originalRanges: [(start: Int64, end: Int64)]

    private var taskToSegment: [Int: Int] = [:]               // taskIdentifier -> segment index
    private var segmentTasks: [Int: URLSessionDataTask] = [:]  // segment index -> task
    private var segmentFileHandles: [Int: FileHandle] = [:]    // segment index -> file handle for writing
    private var segmentFilePaths: [Int: URL] = [:]             // segment index -> temp file path
    private(set) var segmentBytes: [Int: Int64] = [:]          // segment index -> total bytes written to disk
    private var segmentCompleted: Set<Int> = []                // fully downloaded segments
    private var lastProgressReport: CFAbsoluteTime = 0
    private(set) var isCancelled = false
    private(set) var isThrottled = false
    private var preferredConcurrentSegments: Int

    let onProgress: @MainActor (Int64, Int64) -> Void
    let onComplete: @MainActor (URL) -> Void
    let onError: @MainActor (Error) -> Void

    init(itemId: UUID, segmentCount: Int, totalSize: Int64, fileName: String,
         destinationURL: URL,
         originalRanges: [(start: Int64, end: Int64)],
         onProgress: @escaping @MainActor (Int64, Int64) -> Void,
         onComplete: @escaping @MainActor (URL) -> Void,
         onError: @escaping @MainActor (Error) -> Void) {
        self.itemId = itemId
        self.segmentCount = segmentCount
        self.totalSize = totalSize
        self.fileName = fileName
        self.destinationURL = destinationURL
        self.originalRanges = originalRanges
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
        self.preferredConcurrentSegments = max(1, segmentCount)
    }

    func setPreferredConcurrentSegments(_ count: Int) {
        preferredConcurrentSegments = max(1, min(count, segmentCount))
        applyConcurrencyMode()
    }

    /// Start downloads for all segments, creating temp files on disk.
    func startAllTasks(session: URLSession, url: URL) {
        isCancelled = false

        let tempDir = FileManager.default.temporaryDirectory
        for (index, range) in originalRanges.enumerated() {
            let filePath = tempDir.appendingPathComponent("seg_\(itemId)_\(index).tmp")
            segmentFilePaths[index] = filePath

            // Check if temp file already has data (from a previous partial download)
            let existingBytes: Int64
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
               let size = attrs[.size] as? Int64, size > 0 {
                existingBytes = size
            } else {
                existingBytes = 0
                FileManager.default.createFile(atPath: filePath.path, contents: nil)
            }

            segmentBytes[index] = existingBytes

            let segmentSize = range.end - range.start + 1
            if existingBytes >= segmentSize {
                // This segment is already fully downloaded from a previous session
                segmentCompleted.insert(index)
                continue
            }

            // Open file handle for appending
            guard let handle = FileHandle(forWritingAtPath: filePath.path) else { continue }
            handle.seekToEndOfFile()
            segmentFileHandles[index] = handle

            // Create request with adjusted Range header
            let adjustedStart = range.start + existingBytes
            var request = URLRequest(url: url)
            request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=\(adjustedStart)-\(range.end)", forHTTPHeaderField: "Range")

            let task = session.dataTask(with: request)
            taskToSegment[task.taskIdentifier] = index
            segmentTasks[index] = task
            task.resume()
        }

        // Check if all segments were already complete (edge case: resume with all done)
        applyConcurrencyMode()
        checkAllComplete()
    }

    /// Resume by creating new tasks with adjusted Range headers based on existing temp file sizes.
    func resumeWithNewTasks(session: URLSession, url: URL) {
        isCancelled = false
        taskToSegment.removeAll()
        segmentTasks.removeAll()

        for (index, range) in originalRanges.enumerated() {
            // Skip completed segments
            if segmentCompleted.contains(index) { continue }

            guard let filePath = segmentFilePaths[index] else { continue }

            // Check actual file size on disk (authoritative source of progress)
            let existingBytes: Int64
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
               let size = attrs[.size] as? Int64 {
                existingBytes = size
            } else {
                existingBytes = 0
                FileManager.default.createFile(atPath: filePath.path, contents: nil)
            }
            segmentBytes[index] = existingBytes

            let segmentSize = range.end - range.start + 1
            if existingBytes >= segmentSize {
                segmentCompleted.insert(index)
                continue
            }

            // Open file handle for appending
            guard let handle = FileHandle(forWritingAtPath: filePath.path) else { continue }
            handle.seekToEndOfFile()
            segmentFileHandles[index] = handle

            let adjustedStart = range.start + existingBytes
            var request = URLRequest(url: url)
            request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=\(adjustedStart)-\(range.end)", forHTTPHeaderField: "Range")

            let task = session.dataTask(with: request)
            taskToSegment[task.taskIdentifier] = index
            segmentTasks[index] = task
            task.resume()
        }

        applyConcurrencyMode()
        checkAllComplete()
    }

    /// Cancel all active tasks and close file handles. Temp files are kept on disk.
    func cancelAllTasks() {
        isCancelled = true
        isThrottled = false
        for task in segmentTasks.values {
            task.cancel()
        }
        segmentTasks.removeAll()
        taskToSegment.removeAll()

        // Close all file handles (temp files stay on disk with partial data)
        for handle in segmentFileHandles.values {
            handle.closeFile()
        }
        segmentFileHandles.removeAll()
    }

    /// Suspend tasks for speed throttling only — does NOT set isCancelled.
    func throttleSuspendTasks() {
        isThrottled = true
        for (index, task) in segmentTasks where !segmentCompleted.contains(index) {
            task.suspend()
        }
    }

    /// Resume tasks after speed throttling — does NOT clear isCancelled.
    func throttleResumeTasks() {
        isThrottled = false
        guard !isCancelled else { return }
        applyConcurrencyMode()
    }

    /// Remove all temp files from disk (used on cancel).
    func cleanupTempFiles() {
        for handle in segmentFileHandles.values {
            handle.closeFile()
        }
        segmentFileHandles.removeAll()
        for url in segmentFilePaths.values {
            try? FileManager.default.removeItem(at: url)
        }
        segmentFilePaths.removeAll()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Reject HTTP errors
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            completionHandler(.cancel)
            let error = NSError(domain: "SegmentedDownload", code: http.statusCode,
                               userInfo: [NSLocalizedDescriptionKey: "HTTP error \(http.statusCode)"])
            Task { @MainActor in onError(error) }
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let segIndex = taskToSegment[dataTask.taskIdentifier] else { return }

        // Write data to file immediately
        segmentFileHandles[segIndex]?.write(data)
        segmentBytes[segIndex] = (segmentBytes[segIndex] ?? 0) + Int64(data.count)

        // Report progress periodically
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProgressReport >= 0.25 else { return }
        lastProgressReport = now

        let totalDown = segmentBytes.values.reduce(0, +)
        Task { @MainActor in
            onProgress(totalDown, totalSize)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let segIndex = taskToSegment[task.taskIdentifier] else { return }

        // Close file handle for this segment
        segmentFileHandles[segIndex]?.closeFile()
        segmentFileHandles.removeValue(forKey: segIndex)

        if let error = error as? NSError {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
            // Ignore errors from cancelled/throttled tasks
            if isCancelled || isThrottled { return }
            Task { @MainActor in onError(error) }
            return
        }

        // Segment completed successfully
        segmentCompleted.insert(segIndex)
        segmentTasks.removeValue(forKey: segIndex)

        // Report final progress
        let totalDown = segmentBytes.values.reduce(0, +)
        Task { @MainActor in
            onProgress(totalDown, totalSize)
        }

        applyConcurrencyMode()
        checkAllComplete()
    }

    private func applyConcurrencyMode() {
        guard !isCancelled else { return }

        if isThrottled {
            for task in segmentTasks.values {
                task.suspend()
            }
            return
        }

        let allowedSegments = SegmentedTaskConcurrencyPlanner.allowedSegmentIndices(
            activeSegmentIndices: Array(segmentTasks.keys),
            preferredConcurrentSegments: preferredConcurrentSegments
        )

        for (index, task) in segmentTasks {
            guard !segmentCompleted.contains(index) else { continue }

            if allowedSegments.contains(index) {
                if task.state == .suspended {
                    task.resume()
                }
            } else if task.state == .running {
                task.suspend()
            }
        }
    }

    private func checkAllComplete() {
        guard segmentCompleted.count == segmentCount else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.mergeSegments()
        }
    }

    // Merge all segment files into the final destination
    private func mergeSegments() {
        let destination = destinationURL
        let tempDestination = destination.appendingPathExtension("fetchoradownload")
        let parentDir = destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            // Remove existing files
            try? FileManager.default.removeItem(at: tempDestination)
            try? FileManager.default.removeItem(at: destination)

            // Create output file with temp extension
            FileManager.default.createFile(atPath: tempDestination.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: tempDestination)

            // Write segments in order (stream in chunks to avoid OOM)
            let chunkSize = 4 * 1024 * 1024 // 4 MB
            for i in 0..<segmentCount {
                guard let segURL = segmentFilePaths[i] else {
                    throw NSError(domain: "SegmentedDownload", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing segment \(i)"])
                }
                let segHandle = try FileHandle(forReadingFrom: segURL)
                defer { segHandle.closeFile() }
                while true {
                    let chunk = segHandle.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    fileHandle.write(chunk)
                }
                try? FileManager.default.removeItem(at: segURL)
            }

            fileHandle.closeFile()

            // Rename from .fetchoradownload to final name
            try FileManager.default.moveItem(at: tempDestination, to: destination)

            Task { @MainActor in
                onComplete(destination)
            }
        } catch {
            // Cleanup temp files
            try? FileManager.default.removeItem(at: tempDestination)
            for url in segmentFilePaths.values {
                try? FileManager.default.removeItem(at: url)
            }
            Task { @MainActor in onError(error) }
        }
    }
}

enum SegmentedTaskConcurrencyPlanner {
    static func allowedSegmentIndices(
        activeSegmentIndices: [Int],
        preferredConcurrentSegments: Int
    ) -> Set<Int> {
        guard preferredConcurrentSegments > 0 else { return [] }
        return Set(activeSegmentIndices.sorted().prefix(preferredConcurrentSegments))
    }
}
