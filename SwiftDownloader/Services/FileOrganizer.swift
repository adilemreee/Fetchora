import Foundation

class FileOrganizer {
    static let shared = FileOrganizer()

    private let fileManager = FileManager.default
    private var isAutoCategorizationEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.Keys.autoCategorizationEnabled)
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            Constants.Keys.autoCategorizationEnabled: Constants.defaultAutoCategorizationEnabled
        ])
    }

    var baseDownloadDirectory: URL {
        if let saved = UserDefaults.standard.string(forKey: Constants.Keys.downloadDirectory) {
            return URL(fileURLWithPath: saved)
        }
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    func destinationURL(for fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let category = FileCategory.from(extension: ext)

        if isAutoCategorizationEnabled {
            let categoryDir = baseDownloadDirectory.appendingPathComponent(category.rawValue)
            ensureDirectoryExists(categoryDir)
            return uniqueURL(for: categoryDir.appendingPathComponent(fileName))
        }

        return uniqueURL(for: baseDownloadDirectory.appendingPathComponent(fileName))
    }

    func moveToCategory(fileAt source: URL, category: FileCategory) throws {
        guard isAutoCategorizationEnabled else { return }

        let categoryDir = baseDownloadDirectory.appendingPathComponent(category.rawValue)
        ensureDirectoryExists(categoryDir)

        let destination = uniqueURL(for: categoryDir.appendingPathComponent(source.lastPathComponent))
        try fileManager.moveItem(at: source, to: destination)
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
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
