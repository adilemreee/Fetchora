import XCTest
@testable import Fetchora

final class SchedulerServiceTests: XCTestCase {
    func testNextAutomaticScheduleDateUsesSameDayWhenTimeHasNotPassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 9, minute: 0))!
        let scheduled = ScheduledDownloadPlanner.nextAutomaticScheduleDate(
            isEnabled: true,
            hour: 18,
            minute: 15,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            scheduled,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 18, minute: 15))
        )
    }

    func testNextAutomaticScheduleDateRollsToNextDayWhenTimePassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 21, minute: 0))!
        let scheduled = ScheduledDownloadPlanner.nextAutomaticScheduleDate(
            isEnabled: true,
            hour: 18,
            minute: 15,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            scheduled,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 18, minute: 15))
        )
    }

    func testShouldStartScheduledItemOnlyAfterScheduledDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let scheduledDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 12, minute: 0))!
        let item = DownloadItem(
            url: "https://example.com/file.zip",
            fileName: "file.zip",
            destinationPath: "/tmp/file.zip",
            category: .archive,
            scheduledDate: scheduledDate
        )

        XCTAssertFalse(
            ScheduledDownloadPlanner.shouldStartScheduledItem(
                item,
                now: calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 11, minute: 59))!
            )
        )

        XCTAssertTrue(
            ScheduledDownloadPlanner.shouldStartScheduledItem(
                item,
                now: calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 12, minute: 0))!
            )
        )
    }
}
