import Foundation
import AppKit

/// Downloads a file using multiple concurrent URLSessionDownloadTask instances with HTTP Range headers.
/// Each segment is a fast bulk download. Segments are merged after completion.
/// Falls back to single connection if server doesn't support Range or file is small.
@MainActor
class SegmentedDownloadManager: NSObject, ObservableObject {
    static let shared = SegmentedDownloadManager()

    private var segmentSessions: [UUID: URLSession] = [:]
    private var segmentDelegates: [UUID: SegmentDelegate] = [:]
    private var activeSegmentedDownloads: Set<UUID> = []

    let segmentCount = 4
    let minFileSize: Int64 = 5 * 1024 * 1024 // 5MB minimum for segmented

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
        onProgress: @escaping @MainActor (Int64, Int64) -> Void,
        onComplete: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        activeSegmentedDownloads.insert(itemId)

        Task {
            let info = await checkRangeSupport(url: url)

            guard info.supportsRange && info.contentLength >= minFileSize else {
                // Not suitable for segmented — caller should use normal download
                await MainActor.run {
                    activeSegmentedDownloads.remove(itemId)
                    onError(NSError(domain: "SegmentedDownload", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "USE_NORMAL_DOWNLOAD"]))
                }
                return
            }

            await MainActor.run {
                self.performSegmentedDownload(
                    itemId: itemId,
                    url: url,
                    fileName: fileName,
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
            delegate.cleanupTempFiles()
        }
        segmentSessions[itemId]?.invalidateAndCancel()
        segmentSessions.removeValue(forKey: itemId)
        segmentDelegates.removeValue(forKey: itemId)
        activeSegmentedDownloads.remove(itemId)
    }

    func isSegmented(_ itemId: UUID) -> Bool {
        activeSegmentedDownloads.contains(itemId)
    }

    /// Pause a segmented download by suspending all active tasks.
    /// The session and delegate stay alive so data is preserved.
    func pauseSegmented(itemId: UUID) -> Bool {
        guard let delegate = segmentDelegates[itemId] else { return false }
        delegate.suspendAllTasks()
        activeSegmentedDownloads.remove(itemId)
        return true
    }

    /// Check if there is a paused segmented download that can be resumed.
    func hasPausedSegments(_ itemId: UUID) -> Bool {
        segmentDelegates[itemId] != nil && !activeSegmentedDownloads.contains(itemId)
    }

    /// Resume a previously paused segmented download by resuming suspended tasks.
    func resumeSegmented(itemId: UUID) -> Bool {
        guard let delegate = segmentDelegates[itemId],
              !activeSegmentedDownloads.contains(itemId) else { return false }
        activeSegmentedDownloads.insert(itemId)
        delegate.resumeAllTasks()
        return true
    }

    // MARK: - Private

    private func performSegmentedDownload(
        itemId: UUID,
        url: URL,
        fileName: String,
        totalSize: Int64,
        onProgress: @escaping @MainActor (Int64, Int64) -> Void,
        onComplete: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        let segSize = totalSize / Int64(segmentCount)
        var ranges: [(Int64, Int64)] = []

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
            onProgress: onProgress,
            onComplete: { [weak self] resultURL in
                self?.segmentSessions.removeValue(forKey: itemId)
                self?.segmentDelegates.removeValue(forKey: itemId)
                self?.activeSegmentedDownloads.remove(itemId)
                onComplete(resultURL)
            },
            onError: { [weak self] error in
                self?.segmentSessions.removeValue(forKey: itemId)
                self?.segmentDelegates.removeValue(forKey: itemId)
                self?.activeSegmentedDownloads.remove(itemId)
                onError(error)
            }
        )

        let config = ProxySettings.configuredSessionConfiguration()
        config.httpMaximumConnectionsPerHost = segmentCount
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 24

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        segmentDelegates[itemId] = delegate
        segmentSessions[itemId] = session

        // Start all segment downloads
        for (index, range) in ranges.enumerated() {
            var request = URLRequest(url: url)
            request.setValue("Fetchora/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=\(range.0)-\(range.1)", forHTTPHeaderField: "Range")

            let task = session.downloadTask(with: request)
            delegate.registerTask(task, forSegment: index)
            task.resume()
        }
    }
}

// MARK: - Segment Delegate

/// Handles download callbacks for all segments of a single file download.
private class SegmentDelegate: NSObject, URLSessionDownloadDelegate {
    let itemId: UUID
    let segmentCount: Int
    let totalSize: Int64
    let fileName: String

    private var taskToSegment: [Int: Int] = [:] // taskIdentifier -> segment index
    private var segmentTasks: [Int: URLSessionDownloadTask] = [:] // segment index -> task
    private(set) var segmentFiles: [Int: URL] = [:]
    private var segmentBytes: [Int: Int64] = [:]
    private var completedCount = 0
    private var lastProgressReport: CFAbsoluteTime = 0

    let onProgress: @MainActor (Int64, Int64) -> Void
    let onComplete: @MainActor (URL) -> Void
    let onError: @MainActor (Error) -> Void

    init(itemId: UUID, segmentCount: Int, totalSize: Int64, fileName: String,
         onProgress: @escaping @MainActor (Int64, Int64) -> Void,
         onComplete: @escaping @MainActor (URL) -> Void,
         onError: @escaping @MainActor (Error) -> Void) {
        self.itemId = itemId
        self.segmentCount = segmentCount
        self.totalSize = totalSize
        self.fileName = fileName
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func registerTask(_ task: URLSessionDownloadTask, forSegment index: Int) {
        taskToSegment[task.taskIdentifier] = index
        segmentTasks[index] = task
    }

    /// Suspend all in-progress tasks (preserves downloaded data).
    func suspendAllTasks() {
        for (segIndex, task) in segmentTasks where segmentFiles[segIndex] == nil {
            task.suspend()
        }
    }

    /// Resume all suspended tasks.
    func resumeAllTasks() {
        for (segIndex, task) in segmentTasks where segmentFiles[segIndex] == nil {
            task.resume()
        }
    }

    /// Clean up completed segment temp files (used on cancel).
    func cleanupTempFiles() {
        for url in segmentFiles.values {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // Download progress for each segment
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let segIndex = taskToSegment[downloadTask.taskIdentifier] else { return }
        segmentBytes[segIndex] = totalBytesWritten

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProgressReport >= 0.3 else { return }
        lastProgressReport = now

        let totalDown = segmentBytes.values.reduce(0, +)
        Task { @MainActor in
            onProgress(totalDown, totalSize)
        }
    }

    // Segment completed — save temp file
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let segIndex = taskToSegment[downloadTask.taskIdentifier] else { return }

        // Copy to a safe temp location before URLSession deletes it
        let tempDir = FileManager.default.temporaryDirectory
        let safePath = tempDir.appendingPathComponent("seg_\(itemId)_\(segIndex).tmp")
        try? FileManager.default.removeItem(at: safePath)

        do {
            try FileManager.default.moveItem(at: location, to: safePath)
            segmentFiles[segIndex] = safePath
            completedCount += 1

            // All segments done — merge
            if completedCount == segmentCount {
                mergeSegments()
            }
        } catch {
            Task { @MainActor in onError(error) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as? NSError else { return }
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        Task { @MainActor in onError(error) }
    }

    // Merge all segment files into the final destination
    private func mergeSegments() {
        let destination = FileOrganizer.shared.destinationURL(for: fileName)
        let parentDir = destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            // Remove existing file
            try? FileManager.default.removeItem(at: destination)

            // Create output file
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: destination)

            // Write segments in order
            for i in 0..<segmentCount {
                guard let segURL = segmentFiles[i] else {
                    throw NSError(domain: "SegmentedDownload", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing segment \(i)"])
                }
                let data = try Data(contentsOf: segURL)
                fileHandle.write(data)
                try? FileManager.default.removeItem(at: segURL)
            }

            fileHandle.closeFile()

            Task { @MainActor in
                onComplete(destination)
            }
        } catch {
            // Cleanup temp files
            for url in segmentFiles.values {
                try? FileManager.default.removeItem(at: url)
            }
            Task { @MainActor in onError(error) }
        }
    }
}
