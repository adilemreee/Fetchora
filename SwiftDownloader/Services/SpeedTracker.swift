import Foundation

/// Tracks download speed using a sliding window with exponential moving average (EMA) smoothing.
/// Produces stable, non-jittery speed values suitable for UI display.
class SpeedTracker: @unchecked Sendable {
    private struct Sample {
        let timestamp: CFAbsoluteTime
        let bytes: Int64
    }

    private var samples: [Sample] = []
    private let windowSize: TimeInterval = 5.0
    private let lock = NSLock()
    private var _smoothedSpeed: Double = 0
    private let smoothingFactor: Double = 0.25 // EMA alpha — lower = smoother

    var currentSpeed: Double {
        lock.lock()
        defer { lock.unlock() }
        return max(_smoothedSpeed, 0)
    }

    func addSample(totalBytes: Int64) {
        lock.lock()
        defer { lock.unlock()  }

        let now = CFAbsoluteTimeGetCurrent()
        samples.append(Sample(timestamp: now, bytes: totalBytes))

        // Remove samples outside the window
        samples.removeAll { now - $0.timestamp > windowSize }

        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else { return }

        let timeDiff = last.timestamp - first.timestamp
        guard timeDiff > 0.2 else { return } // Need at least 200ms for meaningful measurement

        let bytesDiff = Double(last.bytes - first.bytes)
        let rawSpeed = max(bytesDiff / timeDiff, 0)

        // Apply exponential moving average for smoothing
        if _smoothedSpeed < 1 {
            _smoothedSpeed = rawSpeed
        } else {
            _smoothedSpeed = smoothingFactor * rawSpeed + (1.0 - smoothingFactor) * _smoothedSpeed
        }
    }

    func estimatedTimeRemaining(totalBytes: Int64, downloadedBytes: Int64) -> TimeInterval {
        let speed = currentSpeed
        guard speed > 100 else { return .infinity } // Need at least 100 B/s for meaningful ETA
        let remaining = Double(totalBytes - downloadedBytes)
        return remaining / speed
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        _smoothedSpeed = 0
    }
}
