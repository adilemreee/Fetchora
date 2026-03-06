import Foundation

enum ScheduledDownloadPlanner {
    static func nextAutomaticScheduleDate(
        isEnabled: Bool,
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard isEnabled else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0

        guard let todayAtConfiguredTime = calendar.date(from: components) else { return nil }
        if todayAtConfiguredTime > now {
            return todayAtConfiguredTime
        }

        return calendar.date(byAdding: .day, value: 1, to: todayAtConfiguredTime)
    }

    static func shouldStartScheduledItem(_ item: DownloadItem, now: Date = Date()) -> Bool {
        guard item.status == .scheduled, let scheduledDate = item.scheduledDate else { return false }
        return scheduledDate <= now
    }
}
