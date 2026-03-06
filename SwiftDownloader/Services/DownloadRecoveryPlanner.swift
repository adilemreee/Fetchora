import Foundation

enum DownloadRecoveryPlanner {
    static func shouldRecoverOnLaunch(status: DownloadStatus) -> Bool {
        status == .downloading || status == .waiting
    }

    static func itemsNeedingRecovery(from items: [DownloadItem]) -> [DownloadItem] {
        items.filter { shouldRecoverOnLaunch(status: $0.status) }
    }
}
