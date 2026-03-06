import XCTest
@testable import Fetchora

final class DownloadTrafficLimiterTests: XCTestCase {
    func testLimiterSuspendsWhenMeasuredRateExceedsLimit() {
        let limiter = DownloadTrafficLimiter()

        XCTAssertEqual(
            limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 0, activeDownloadCount: 1, now: 10),
            .none
        )

        XCTAssertEqual(
            limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 3_072, activeDownloadCount: 1, now: 10.5),
            .suspendAll
        )

        XCTAssertTrue(limiter.isSuspended)
        XCTAssertGreaterThan(limiter.suspendDuration, 0)
    }

    func testLimiterResumesAfterSuspendWindowExpires() {
        let limiter = DownloadTrafficLimiter()
        _ = limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 0, activeDownloadCount: 1, now: 20)
        _ = limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 3_072, activeDownloadCount: 1, now: 20.5)

        XCTAssertEqual(
            limiter.evaluate(
                limitBytesPerSecond: 1_024,
                totalDownloadedBytes: 3_072,
                activeDownloadCount: 1,
                now: 20.5 + limiter.suspendDuration - 0.01
            ),
            .none
        )

        XCTAssertEqual(
            limiter.evaluate(
                limitBytesPerSecond: 1_024,
                totalDownloadedBytes: 3_072,
                activeDownloadCount: 1,
                now: 20.5 + limiter.suspendDuration + 0.01
            ),
            .resumeAll
        )

        XCTAssertFalse(limiter.isSuspended)
    }

    func testLimiterResetsWhenLimitBecomesUnlimited() {
        let limiter = DownloadTrafficLimiter()
        _ = limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 0, activeDownloadCount: 1, now: 30)
        _ = limiter.evaluate(limitBytesPerSecond: 1_024, totalDownloadedBytes: 3_072, activeDownloadCount: 1, now: 30.5)

        XCTAssertEqual(
            limiter.evaluate(limitBytesPerSecond: 0, totalDownloadedBytes: 3_072, activeDownloadCount: 1, now: 31),
            .reset
        )

        XCTAssertFalse(limiter.isSuspended)
        XCTAssertEqual(limiter.suspendDuration, 0)
    }
}
