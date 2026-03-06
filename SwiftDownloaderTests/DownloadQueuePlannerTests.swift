import XCTest
@testable import Fetchora

final class DownloadQueuePlannerTests: XCTestCase {
    func testOrderedPendingQueuePrefersHigherPriorityThenOlderItems() {
        let low = makeItem(name: "low.zip", priority: .low, secondsOffset: 30)
        let normal = makeItem(name: "normal.zip", priority: .normal, secondsOffset: 20)
        let highNew = makeItem(name: "high-new.zip", priority: .high, secondsOffset: 10)
        let highOld = makeItem(name: "high-old.zip", priority: .high, secondsOffset: 0)

        let ordered = DownloadQueuePlanner.orderedPendingQueue([low, highNew, normal, highOld])

        XCTAssertEqual(ordered.map(\.fileName), ["high-old.zip", "high-new.zip", "normal.zip", "low.zip"])
    }

    func testNextItemsToStartRespectsConcurrentSlots() {
        let items = [
            makeItem(name: "normal.zip", priority: .normal, secondsOffset: 0),
            makeItem(name: "high.zip", priority: .high, secondsOffset: 10),
            makeItem(name: "low.zip", priority: .low, secondsOffset: 20)
        ]

        let nextItems = DownloadQueuePlanner.nextItemsToStart(
            activeCount: 1,
            maxConcurrent: 3,
            pendingQueue: items
        )

        XCTAssertEqual(nextItems.map(\.fileName), ["high.zip", "normal.zip"])
    }

    func testMergedPendingQueueAddsWaitingItemsMissingFromTrackedQueue() {
        let trackedNormal = makeItem(name: "tracked-normal.zip", priority: .normal, secondsOffset: 10)
        let missingHigh = makeItem(name: "missing-high.zip", priority: .high, secondsOffset: 0)

        let merged = DownloadQueuePlanner.mergedPendingQueue(
            trackedQueue: [trackedNormal],
            allWaitingItems: [missingHigh]
        )

        XCTAssertEqual(merged.map(\.fileName), ["missing-high.zip", "tracked-normal.zip"])
    }

    func testPreemptionDecisionYieldsLowerPriorityActiveDownload() {
        let activeLow = makeItem(name: "active-low.zip", priority: .low, secondsOffset: 20)
        let activeNormal = makeItem(name: "active-normal.zip", priority: .normal, secondsOffset: 10)
        let pendingHigh = makeItem(name: "pending-high.zip", priority: .high, secondsOffset: 0)

        let decision = DownloadQueuePlanner.preemptionDecision(
            activeItems: [activeLow, activeNormal],
            pendingQueue: [pendingHigh],
            maxConcurrent: 2
        )

        XCTAssertEqual(decision?.activeItemToYield.fileName, "active-low.zip")
        XCTAssertEqual(decision?.pendingItemToPromote.fileName, "pending-high.zip")
    }

    func testPreemptionDecisionDoesNothingForEqualPriority() {
        let activeHigh = makeItem(name: "active-high.zip", priority: .high, secondsOffset: 0)
        let pendingHigh = makeItem(name: "pending-high.zip", priority: .high, secondsOffset: 10)

        let decision = DownloadQueuePlanner.preemptionDecision(
            activeItems: [activeHigh],
            pendingQueue: [pendingHigh],
            maxConcurrent: 1
        )

        XCTAssertNil(decision)
    }

    private func makeItem(name: String, priority: DownloadPriority, secondsOffset: TimeInterval) -> DownloadItem {
        let item = DownloadItem(
            url: "https://example.com/\(name)",
            fileName: name,
            destinationPath: "/tmp/\(name)",
            category: .archive,
            priority: priority
        )
        item.dateAdded = Date(timeIntervalSince1970: 1_000 + secondsOffset)
        return item
    }
}
