import Foundation
import SwiftData

enum DownloadStatus: String, Codable {
    case waiting = "Waiting"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case scheduled = "Scheduled"

    var iconName: String {
        switch self {
        case .waiting: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .scheduled: return "calendar.circle"
        }
    }

    var localizedName: String {
        switch self {
        case .waiting: return NSLocalizedString("status.waiting", comment: "")
        case .downloading: return NSLocalizedString("status.downloading", comment: "")
        case .paused: return NSLocalizedString("status.paused", comment: "")
        case .completed: return NSLocalizedString("status.completed", comment: "")
        case .failed: return NSLocalizedString("status.failed", comment: "")
        case .cancelled: return NSLocalizedString("status.cancelled", comment: "")
        case .scheduled: return NSLocalizedString("status.scheduled", comment: "")
        }
    }

    var isActive: Bool {
        self == .downloading || self == .waiting
    }
}

enum DownloadPriority: String, Codable, CaseIterable {
    case high = "High"
    case normal = "Normal"
    case low = "Low"

    var localizedName: String {
        switch self {
        case .high: return NSLocalizedString("priority.high", comment: "")
        case .normal: return NSLocalizedString("priority.normal", comment: "")
        case .low: return NSLocalizedString("priority.low", comment: "")
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    var icon: String {
        switch self {
        case .high: return "arrow.up.circle.fill"
        case .normal: return "minus.circle.fill"
        case .low: return "arrow.down.circle"
        }
    }
}

@Model
final class DownloadItem {
    @Attribute(.unique) var id: UUID
    var url: String
    var fileName: String
    var destinationPath: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var status: DownloadStatus
    var category: FileCategory
    var priority: DownloadPriority?
    var dateAdded: Date
    var dateCompleted: Date?
    var scheduledDate: Date?
    var resumeData: Data?
    var errorMessage: String?
    var mimeType: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var progressPercentage: String {
        String(format: "%.1f%%", progress * 100)
    }

    var safePriority: DownloadPriority {
        priority ?? .normal
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }

    init(
        url: String,
        fileName: String,
        destinationPath: String,
        category: FileCategory = .other,
        scheduledDate: Date? = nil,
        priority: DownloadPriority = .normal
    ) {
        self.id = UUID()
        self.url = url
        self.fileName = fileName
        self.destinationPath = destinationPath
        self.totalBytes = 0
        self.downloadedBytes = 0
        self.status = scheduledDate != nil ? .scheduled : .waiting
        self.category = category
        self.priority = priority
        self.dateAdded = Date()
        self.scheduledDate = scheduledDate
    }
}
