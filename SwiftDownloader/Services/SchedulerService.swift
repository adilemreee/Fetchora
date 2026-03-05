import Foundation
import Combine

class SchedulerService: ObservableObject {
    static let shared = SchedulerService()

    @Published var scheduledItems: [DownloadSchedule] = []
    private var timer: Timer?

    private init() {
        startMonitoring()
    }

    func schedule(downloadId: UUID, at date: Date, recurring: Bool = false, interval: RepeatInterval? = nil) {
        let schedule = DownloadSchedule(
            downloadId: downloadId,
            scheduledDate: date,
            isRecurring: recurring,
            repeatInterval: interval
        )
        scheduledItems.append(schedule)
    }

    func removeSchedule(for downloadId: UUID) {
        scheduledItems.removeAll { $0.downloadId == downloadId }
    }

    func toggleSchedule(id: UUID) {
        if let index = scheduledItems.firstIndex(where: { $0.id == id }) {
            scheduledItems[index].isEnabled.toggle()
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkScheduledDownloads()
        }
    }

    private func checkScheduledDownloads() {
        let now = Date()
        let readyItems = scheduledItems.filter { $0.isEnabled && $0.scheduledDate <= now }

        for item in readyItems {
            NotificationCenter.default.post(
                name: Constants.Notifications.newDownloadRequested,
                object: nil,
                userInfo: ["downloadId": item.downloadId]
            )

            if item.isRecurring, let interval = item.repeatInterval {
                reschedule(item, interval: interval)
            } else {
                removeSchedule(for: item.downloadId)
            }
        }
    }

    private func reschedule(_ schedule: DownloadSchedule, interval: RepeatInterval) {
        guard let index = scheduledItems.firstIndex(where: { $0.id == schedule.id }) else { return }

        var nextDate = schedule.scheduledDate
        switch interval {
        case .daily:
            nextDate = Calendar.current.date(byAdding: .day, value: 1, to: nextDate)!
        case .weekly:
            nextDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: nextDate)!
        case .monthly:
            nextDate = Calendar.current.date(byAdding: .month, value: 1, to: nextDate)!
        }
        scheduledItems[index].scheduledDate = nextDate
    }

    deinit {
        timer?.invalidate()
    }
}
