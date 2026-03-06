import Foundation

enum DuplicateDownloadResolver {
    static func normalizedURLString(_ rawURL: String) -> String? {
        guard var components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if let scheme = components.scheme, let port = components.port {
            if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) {
                components.port = nil
            }
        }

        return components.url?.absoluteString ?? components.string
    }

    static func uniqueFileName(for requestedFileName: String, existingFileNames: [String]) -> String {
        var candidate = requestedFileName
        let existingNames = Set(existingFileNames)

        let baseName = (requestedFileName as NSString).deletingPathExtension
        let pathExtension = (requestedFileName as NSString).pathExtension
        var counter = 1

        while existingNames.contains(candidate) {
            candidate = pathExtension.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(pathExtension)"
            counter += 1
        }

        return candidate
    }

    static func existingItem(forURL requestedURL: String, existingItems: [DownloadItem]) -> DownloadItem? {
        guard let normalizedRequestedURL = normalizedURLString(requestedURL) else {
            return nil
        }

        return existingItems.first { item in
            shouldTreatAsExistingDownload(item) &&
            normalizedURLString(item.url) == normalizedRequestedURL
        }
    }

    static func existingItem(forFileName requestedFileName: String, existingItems: [DownloadItem]) -> DownloadItem? {
        existingItems.first { item in
            item.fileName == requestedFileName && shouldTreatAsExistingDownload(item)
        }
    }

    static func overwriteDestination(for requestedFileName: String, existingItems: [DownloadItem]) -> URL {
        if let existingItem = existingItem(forFileName: requestedFileName, existingItems: existingItems) {
            return URL(fileURLWithPath: existingItem.destinationPath)
        }

        return FileOrganizer.shared.destinationURL(for: requestedFileName, overwriteExisting: true)
    }

    private static func shouldTreatAsExistingDownload(_ item: DownloadItem) -> Bool {
        switch item.status {
        case .failed, .cancelled:
            return false
        case .completed:
            return item.fileExists
        case .waiting, .downloading, .paused, .scheduled:
            return true
        }
    }
}
