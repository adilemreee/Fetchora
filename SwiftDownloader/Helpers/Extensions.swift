import Foundation

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

extension Double {
    var formattedSpeed: String {
        let bytesPerSecond = Int64(self)
        if bytesPerSecond < 1024 {
            return "\(bytesPerSecond) B/s"
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", self / 1024)
        } else if bytesPerSecond < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", self / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", self / (1024 * 1024 * 1024))
        }
    }
}

extension TimeInterval {
    var formattedETA: String {
        if self.isInfinite || self.isNaN || self < 0 {
            return "∞"
        }
        let totalSeconds = Int(self)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}

extension URL {
    var fileExtensionLowercased: String {
        pathExtension.lowercased()
    }

    var isBrowserManagedDownloadURL: Bool {
        let normalizedScheme = scheme?.lowercased()
        return normalizedScheme == "blob" || normalizedScheme == "data"
    }

    var isNetworkDownloadURL: Bool {
        let normalizedScheme = scheme?.lowercased()
        return normalizedScheme == "http" || normalizedScheme == "https"
    }

    var isDownloadableFile: Bool {
        Constants.downloadableExtensions.contains(fileExtensionLowercased)
    }

    var fileCategory: FileCategory {
        FileCategory.from(extension: fileExtensionLowercased)
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
