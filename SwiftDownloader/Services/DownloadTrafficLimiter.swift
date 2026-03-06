import Foundation

enum DownloadTrafficLimitDecision: Equatable {
    case none
    case suspendAll
    case resumeAll
    case reset
}

final class DownloadTrafficLimiter {
    private(set) var isSuspended = false
    private(set) var suspendDuration: TimeInterval = 0

    private var suspendedAt: CFAbsoluteTime = 0
    private var bytesAtWindowStart: Int64 = 0
    private var windowStartTime: CFAbsoluteTime = 0

    func evaluate(
        limitBytesPerSecond: Double,
        totalDownloadedBytes: Int64,
        activeDownloadCount: Int,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) -> DownloadTrafficLimitDecision {
        guard limitBytesPerSecond > 0 else {
            let hadState = hasState
            reset()
            return hadState ? .reset : .none
        }

        guard activeDownloadCount > 0 else {
            reset()
            return .none
        }

        if isSuspended {
            guard now - suspendedAt >= suspendDuration else {
                return .none
            }

            isSuspended = false
            suspendedAt = 0
            bytesAtWindowStart = totalDownloadedBytes
            windowStartTime = now
            suspendDuration = 0
            return .resumeAll
        }

        if windowStartTime == 0 {
            bytesAtWindowStart = totalDownloadedBytes
            windowStartTime = now
            return .none
        }

        let timeSinceWindowStart = now - windowStartTime
        guard timeSinceWindowStart > 0.1 else {
            return .none
        }

        let bytesSinceWindowStart = Double(totalDownloadedBytes - bytesAtWindowStart)
        let currentRate = bytesSinceWindowStart / timeSinceWindowStart

        if currentRate > limitBytesPerSecond * 1.02 {
            let ratio = limitBytesPerSecond / currentRate
            suspendDuration = min(max((1.0 - ratio) * 1.0, 0.1), 1.5)
            suspendedAt = now
            isSuspended = true
            return .suspendAll
        }

        if timeSinceWindowStart > 2.0 {
            bytesAtWindowStart = totalDownloadedBytes
            windowStartTime = now
        }

        return .none
    }

    func reset() {
        isSuspended = false
        suspendDuration = 0
        suspendedAt = 0
        bytesAtWindowStart = 0
        windowStartTime = 0
    }

    private var hasState: Bool {
        isSuspended || suspendDuration > 0 || suspendedAt > 0 || bytesAtWindowStart > 0 || windowStartTime > 0
    }
}
