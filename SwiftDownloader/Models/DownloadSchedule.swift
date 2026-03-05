import Foundation

struct DownloadSchedule: Identifiable, Codable {
    let id: UUID
    var downloadId: UUID
    var scheduledDate: Date
    var isRecurring: Bool
    var repeatInterval: RepeatInterval?
    var isEnabled: Bool

    init(downloadId: UUID, scheduledDate: Date, isRecurring: Bool = false, repeatInterval: RepeatInterval? = nil) {
        self.id = UUID()
        self.downloadId = downloadId
        self.scheduledDate = scheduledDate
        self.isRecurring = isRecurring
        self.repeatInterval = repeatInterval
        self.isEnabled = true
    }
}

enum RepeatInterval: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var localizedName: String {
        switch self {
        case .daily: return NSLocalizedString("repeat.daily", comment: "")
        case .weekly: return NSLocalizedString("repeat.weekly", comment: "")
        case .monthly: return NSLocalizedString("repeat.monthly", comment: "")
        }
    }
}
