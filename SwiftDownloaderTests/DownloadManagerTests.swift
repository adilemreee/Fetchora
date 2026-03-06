import XCTest
@testable import Fetchora

final class DownloadManagerTests: XCTestCase {
    @MainActor
    func testShouldRecoverOnlyWaitingAndDownloadingItems() {
        XCTAssertTrue(DownloadManager.shouldRecoverOnLaunch(status: .waiting))
        XCTAssertTrue(DownloadManager.shouldRecoverOnLaunch(status: .downloading))

        XCTAssertFalse(DownloadManager.shouldRecoverOnLaunch(status: .paused))
        XCTAssertFalse(DownloadManager.shouldRecoverOnLaunch(status: .completed))
        XCTAssertFalse(DownloadManager.shouldRecoverOnLaunch(status: .failed))
        XCTAssertFalse(DownloadManager.shouldRecoverOnLaunch(status: .cancelled))
        XCTAssertFalse(DownloadManager.shouldRecoverOnLaunch(status: .scheduled))
    }
}
