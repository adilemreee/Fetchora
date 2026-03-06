import XCTest
@testable import Fetchora

final class SegmentedTaskConcurrencyPlannerTests: XCTestCase {
    func testAllowedSegmentIndicesKeepsOnlyOneSegmentWhenConstrained() {
        let allowed = SegmentedTaskConcurrencyPlanner.allowedSegmentIndices(
            activeSegmentIndices: [3, 1, 2, 0],
            preferredConcurrentSegments: 1
        )

        XCTAssertEqual(allowed, Set([0]))
    }

    func testAllowedSegmentIndicesKeepsExpectedNumberOfSegments() {
        let allowed = SegmentedTaskConcurrencyPlanner.allowedSegmentIndices(
            activeSegmentIndices: [4, 2, 1, 3],
            preferredConcurrentSegments: 2
        )

        XCTAssertEqual(allowed, Set([1, 2]))
    }
}
