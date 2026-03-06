import Foundation

class FileOrganizer {
    static let shared = FileOrganizer()

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private var activeSecurityScopedDirectory: URL?

    private var isAutoCategorizationEnabled: Bool {
        defaults.bool(forKey: Constants.Keys.autoCategorizationEnabled)
    }

    private init() {
        defaults.register(defaults: [
            Constants.Keys.autoCategorizationEnabled: Constants.defaultAutoCategorizationEnabled
        ])
        _ = restorePersistedDirectoryAccess()
    }

    var baseDownloadDirectory: URL {
        if let scopedURL = restorePersistedDirectoryAccess() {
            return scopedURL
        }

        if let saved = defaults.string(forKey: Constants.Keys.downloadDirectory) {
            return URL(fileURLWithPath: saved)
        }
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    @discardableResult
    func setBaseDownloadDirectory(_ url: URL) -> Bool {
        stopAccessingPersistedDirectory()
        defaults.set(url.path, forKey: Constants.Keys.downloadDirectory)

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Constants.Keys.downloadDirectoryBookmark)
        } catch {
            defaults.removeObject(forKey: Constants.Keys.downloadDirectoryBookmark)
        }

        return restorePersistedDirectoryAccess() != nil || url.path == baseDownloadDirectory.path
    }

    func destinationURL(for fileName: String, overwriteExisting: Bool = false, preferredDirectory: URL? = nil) -> URL {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let category = FileCategory.from(extension: ext)
        let baseDirectory = preferredDirectory ?? destinationDirectory(for: category)

        ensureDirectoryExists(baseDirectory)
        let proposedURL = baseDirectory.appendingPathComponent(fileName)
        return overwriteExisting ? proposedURL : uniqueURL(for: proposedURL)
    }

    func moveToCategory(fileAt source: URL, category: FileCategory) throws {
        guard isAutoCategorizationEnabled else { return }

        let categoryDir = destinationDirectory(for: category)
        ensureDirectoryExists(categoryDir)

        let destination = uniqueURL(for: categoryDir.appendingPathComponent(source.lastPathComponent))
        try fileManager.moveItem(at: source, to: destination)
    }

    func placeholderURL(for destination: URL) -> URL {
        destination.appendingPathExtension("fetchoradownload")
    }

    func removePlaceholder(for destinationPath: String) {
        let placeholder = placeholderURL(for: URL(fileURLWithPath: destinationPath))
        try? fileManager.removeItem(at: placeholder)
    }

    func prepareOverwrite(at destination: URL) {
        ensureDirectoryExists(destination.deletingLastPathComponent())
        try? fileManager.removeItem(at: destination)
        try? fileManager.removeItem(at: placeholderURL(for: destination))
    }

    func restorePersistedDirectoryAccess() -> URL? {
        if let activeSecurityScopedDirectory {
            return activeSecurityScopedDirectory
        }

        guard let bookmarkData = defaults.data(forKey: Constants.Keys.downloadDirectoryBookmark) else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            _ = setBaseDownloadDirectory(resolvedURL)
        }

        if resolvedURL.startAccessingSecurityScopedResource() {
            activeSecurityScopedDirectory = resolvedURL
        }

        return activeSecurityScopedDirectory ?? resolvedURL
    }

    func stopAccessingPersistedDirectory() {
        activeSecurityScopedDirectory?.stopAccessingSecurityScopedResource()
        activeSecurityScopedDirectory = nil
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func destinationDirectory(for category: FileCategory) -> URL {
        if isAutoCategorizationEnabled {
            return baseDownloadDirectory.appendingPathComponent(category.rawValue)
        }

        return baseDownloadDirectory
    }

    private func uniqueURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL: URL
        repeat {
            let newName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            newURL = directory.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: newURL.path)

        return newURL
    }
}
