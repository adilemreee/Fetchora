import Foundation

class SpeedTracker: @unchecked Sendable {
    private var samples: [(timestamp: Date, bytes: Int64)] = []
    private let windowSize: TimeInterval = 3.0
    private let lock = NSLock()

    var currentSpeed: Double {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        samples.removeAll { now.timeIntervalSince($0.timestamp) > windowSize }

        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else { return 0 }

        let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDiff > 0 else { return 0 }

        let bytesDiff = last.bytes - first.bytes
        return Double(bytesDiff) / timeDiff
    }

    func addSample(totalBytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        samples.append((timestamp: Date(), bytes: totalBytes))

        let now = Date()
        samples.removeAll { now.timeIntervalSince($0.timestamp) > windowSize * 2 }
    }

    func estimatedTimeRemaining(totalBytes: Int64, downloadedBytes: Int64) -> TimeInterval {
        let speed = currentSpeed
        guard speed > 0 else { return .infinity }
        let remaining = Double(totalBytes - downloadedBytes)
        return remaining / speed
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
