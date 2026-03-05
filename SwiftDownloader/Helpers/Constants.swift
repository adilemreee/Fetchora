import Foundation

enum Constants {
    static let appName = "Fetchora"
    static let appGroupIdentifier = "group.com.adilemre.SwiftDownloader"

    // Download defaults
    static let defaultMaxConcurrentDownloads = 1
    static let defaultSpeedLimitPreset: String = "high" // high = unlimited
    static let defaultAutoCategorizationEnabled = true

    // File categories with extensions
    static let downloadableExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
        "dmg", "pkg", "iso", "img",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv",
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v",
        "mp3", "wav", "flac", "aac", "ogg", "wma", "m4a",
        "jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "tiff", "ico",
        "exe", "msi", "deb", "rpm", "app",
        "json", "xml", "html", "css", "js", "py", "swift", "java",
        "torrent"
    ]

    static let categoryMappings: [FileCategory: Set<String>] = [
        .video: ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v"],
        .audio: ["mp3", "wav", "flac", "aac", "ogg", "wma", "m4a"],
        .document: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv"],
        .image: ["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "tiff", "ico"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"],
        .application: ["dmg", "pkg", "iso", "img", "exe", "msi", "deb", "rpm", "app"],
        .code: ["json", "xml", "html", "css", "js", "py", "swift", "java"]
    ]

    // UserDefaults keys
    enum Keys {
        static let downloadDirectory = "downloadDirectory"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let speedLimitPreset = "speedLimitPreset"
        static let speedLimitCustomKBps = "speedLimitCustomKBps"
        static let autoCategorizationEnabled = "autoCategorizationEnabled"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let launchAtLogin = "launchAtLogin"
        static let startMinimized = "startMinimized"
        static let hideFromDock = "hideFromDock"
        static let soundEnabled = "soundEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let autoRetryEnabled = "autoRetryEnabled"
        static let autoRetryCount = "autoRetryCount"
        static let completionAction = "completionAction"
        static let proxyEnabled = "proxyEnabled"
        static let proxyType = "proxyType"
        static let proxyHost = "proxyHost"
        static let proxyPort = "proxyPort"
        static let proxyUsername = "proxyUsername"
        static let proxyPassword = "proxyPassword"
        static let clipboardMonitoring = "clipboardMonitoring"
        static let themeMode = "themeMode" // system, dark, light
        static let scheduledDownloadEnabled = "scheduledDownloadEnabled"
        static let scheduledDownloadHour = "scheduledDownloadHour"
        static let scheduledDownloadMinute = "scheduledDownloadMinute"
        static let autoExtractArchives = "autoExtractArchives"
        static let urlRules = "urlRules"
        static let autoRemoveDeletedFiles = "autoRemoveDeletedFiles"
        static let autoRemoveCompleted = "autoRemoveCompleted"
        static let deleteConfirmation = "deleteConfirmation" // ask, removeOnly, deleteFile
    }

    // Notification names
    enum Notifications {
        static let newDownloadRequested = Notification.Name("newDownloadRequested")
        static let downloadProgressUpdated = Notification.Name("downloadProgressUpdated")
        static let downloadCompleted = Notification.Name("downloadCompleted")
        static let showMainWindow = Notification.Name("showMainWindow")
    }
}

enum FileCategory: String, CaseIterable, Codable {
    case video = "Videos"
    case audio = "Music"
    case document = "Documents"
    case image = "Images"
    case archive = "Archives"
    case application = "Applications"
    case code = "Code"
    case other = "Other"

    var localizedName: String {
        switch self {
        case .video: return NSLocalizedString("category.videos", comment: "")
        case .audio: return NSLocalizedString("category.music", comment: "")
        case .document: return NSLocalizedString("category.documents", comment: "")
        case .image: return NSLocalizedString("category.images", comment: "")
        case .archive: return NSLocalizedString("category.archives", comment: "")
        case .application: return NSLocalizedString("category.applications", comment: "")
        case .code: return NSLocalizedString("category.code", comment: "")
        case .other: return NSLocalizedString("category.other", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .image: return "photo"
        case .archive: return "archivebox"
        case .application: return "app.badge"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "questionmark.folder"
        }
    }

    var color: String {
        switch self {
        case .video: return "EF4444"
        case .audio: return "8B5CF6"
        case .document: return "3B82F6"
        case .image: return "10B981"
        case .archive: return "F59E0B"
        case .application: return "EC4899"
        case .code: return "6366F1"
        case .other: return "6B7280"
        }
    }

    static func from(extension ext: String) -> FileCategory {
        for (category, extensions) in Constants.categoryMappings {
            if extensions.contains(ext.lowercased()) {
                return category
            }
        }
        return .other
    }
}
