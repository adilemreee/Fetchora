import Foundation

struct DownloadQueuePreemptionDecision {
    let activeItemToYield: DownloadItem
    let pendingItemToPromote: DownloadItem
}

enum DownloadQueuePlanner {
    static func orderedPendingQueue(_ items: [DownloadItem]) -> [DownloadItem] {
        items.sorted { lhs, rhs in
            if lhs.safePriority.sortOrder != rhs.safePriority.sortOrder {
                return lhs.safePriority.sortOrder < rhs.safePriority.sortOrder
            }

            if lhs.dateAdded != rhs.dateAdded {
                return lhs.dateAdded < rhs.dateAdded
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func mergedPendingQueue(
        trackedQueue: [DownloadItem],
        allWaitingItems: [DownloadItem]
    ) -> [DownloadItem] {
        var itemsById: [UUID: DownloadItem] = [:]

        for item in trackedQueue {
            itemsById[item.id] = item
        }

        for item in allWaitingItems {
            itemsById[item.id] = item
        }

        return orderedPendingQueue(Array(itemsById.values))
    }

    static func nextItemsToStart(
        activeCount: Int,
        maxConcurrent: Int,
        pendingQueue: [DownloadItem]
    ) -> [DownloadItem] {
        let availableSlots = max(maxConcurrent - activeCount, 0)
        guard availableSlots > 0 else { return [] }
        return Array(orderedPendingQueue(pendingQueue).prefix(availableSlots))
    }

    static func preemptionDecision(
        activeItems: [DownloadItem],
        pendingQueue: [DownloadItem],
        maxConcurrent: Int
    ) -> DownloadQueuePreemptionDecision? {
        guard activeItems.count >= maxConcurrent,
              let highestPending = orderedPendingQueue(pendingQueue).first,
              let lowestActive = activeItems.sorted(by: isWorsePriorityCandidate).first,
              highestPending.safePriority.sortOrder < lowestActive.safePriority.sortOrder else {
            return nil
        }

        return DownloadQueuePreemptionDecision(
            activeItemToYield: lowestActive,
            pendingItemToPromote: highestPending
        )
    }

    private static func isWorsePriorityCandidate(_ lhs: DownloadItem, _ rhs: DownloadItem) -> Bool {
        if lhs.safePriority.sortOrder != rhs.safePriority.sortOrder {
            return lhs.safePriority.sortOrder > rhs.safePriority.sortOrder
        }

        if lhs.dateAdded != rhs.dateAdded {
            return lhs.dateAdded > rhs.dateAdded
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }
}
