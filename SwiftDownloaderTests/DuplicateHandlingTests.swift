import XCTest
@testable import Fetchora

final class DuplicateHandlingTests: XCTestCase {
    func testExistingItemForURLIgnoresCancelledAndMissingCompletedItems() {
        let cancelled = DownloadItem(
            url: "https://example.com/file.zip",
            fileName: "file.zip",
            destinationPath: "/tmp/file.zip",
            category: .archive
        )
        cancelled.status = .cancelled

        let completedMissingFile = DownloadItem(
            url: "https://example.com/file.zip#fragment",
            fileName: "file.zip",
            destinationPath: "/tmp/missing-file.zip",
            category: .archive
        )
        completedMissingFile.status = .completed

        XCTAssertNil(
            DuplicateDownloadResolver.existingItem(
                forURL: "https://EXAMPLE.com/file.zip",
                existingItems: [cancelled, completedMissingFile]
            )
        )
    }

    func testExistingItemForURLMatchesNormalizedActiveDownload() {
        let active = DownloadItem(
            url: "https://example.com/file.zip#section",
            fileName: "file.zip",
            destinationPath: "/tmp/file.zip",
            category: .archive
        )
        active.status = .downloading

        let resolved = DuplicateDownloadResolver.existingItem(
            forURL: "https://EXAMPLE.com:443/file.zip",
            existingItems: [active]
        )

        XCTAssertEqual(resolved?.id, active.id)
    }

    func testExistingItemForFileNameIgnoresMissingCompletedFile() {
        let completedMissingFile = DownloadItem(
            url: "https://example.com/archive.zip",
            fileName: "archive.zip",
            destinationPath: "/tmp/does-not-exist/archive.zip",
            category: .archive
        )
        completedMissingFile.status = .completed

        XCTAssertNil(
            DuplicateDownloadResolver.existingItem(
                forFileName: "archive.zip",
                existingItems: [completedMissingFile]
            )
        )
    }

    func testUniqueFileNameAddsCounterAgainstExistingModelNames() {
        let resolved = DuplicateDownloadResolver.uniqueFileName(
            for: "archive.zip",
            existingFileNames: ["archive.zip", "archive (1).zip"]
        )

        XCTAssertEqual(resolved, "archive (2).zip")
    }

    func testOverwriteDestinationPrefersExistingItemPath() {
        let existingItem = DownloadItem(
            url: "https://example.com/archive.zip",
            fileName: "archive.zip",
            destinationPath: "/tmp/custom/archive.zip",
            category: .archive
        )

        let destination = DuplicateDownloadResolver.overwriteDestination(
            for: "archive.zip",
            existingItems: [existingItem]
        )

        XCTAssertEqual(destination.path, "/tmp/custom/archive.zip")
    }
}
