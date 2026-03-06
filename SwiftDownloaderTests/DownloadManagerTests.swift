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

    func testBrowserManagedURLsAreRecognized() {
        XCTAssertTrue(URL(string: "blob:https://chatgpt.com/68f11cc5-bc30-4cbb-84d3-27214e902422")!.isBrowserManagedDownloadURL)
        XCTAssertTrue(URL(string: "data:text/plain;base64,SGVsbG8=")!.isBrowserManagedDownloadURL)
        XCTAssertFalse(URL(string: "https://example.com/file.zip")!.isBrowserManagedDownloadURL)
    }

    func testNetworkDownloadURLsAreRecognized() {
        XCTAssertTrue(URL(string: "https://example.com/file.zip")!.isNetworkDownloadURL)
        XCTAssertTrue(URL(string: "http://example.com/file.zip")!.isNetworkDownloadURL)
        XCTAssertFalse(URL(string: "blob:https://chatgpt.com/68f11cc5-bc30-4cbb-84d3-27214e902422")!.isNetworkDownloadURL)
        XCTAssertFalse(URL(fileURLWithPath: "/tmp/file.zip").isNetworkDownloadURL)
    }
}
