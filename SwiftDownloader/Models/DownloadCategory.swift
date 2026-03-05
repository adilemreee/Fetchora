import Foundation

struct DownloadCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let filter: SidebarFilter

    static let all: [DownloadCategory] = [
        DownloadCategory(id: "all", name: "All Downloads", icon: "arrow.down.circle", filter: .all),
        DownloadCategory(id: "active", name: "Active", icon: "arrow.down.circle.fill", filter: .active),
        DownloadCategory(id: "completed", name: "Completed", icon: "checkmark.circle.fill", filter: .completed),
        DownloadCategory(id: "scheduled", name: "Scheduled", icon: "calendar.circle", filter: .scheduled),
        DownloadCategory(id: "history", name: "History", icon: "clock.arrow.circlepath", filter: .history),
    ]

    static let fileCategories: [DownloadCategory] = FileCategory.allCases.map {
        DownloadCategory(id: $0.rawValue, name: $0.rawValue, icon: $0.iconName, filter: .category($0))
    }
}

enum SidebarFilter: Hashable {
    case all
    case active
    case completed
    case scheduled
    case history
    case category(FileCategory)

    func matches(_ item: DownloadItem) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return item.status == .downloading || item.status == .waiting || item.status == .paused
        case .completed:
            return item.status == .completed
        case .scheduled:
            return item.status == .scheduled
        case .history:
            return item.status == .completed || item.status == .failed || item.status == .cancelled
        case .category(let category):
            return item.category == category
        }
    }
}
