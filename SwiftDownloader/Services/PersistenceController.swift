import AppKit
import Foundation
import SwiftData

@MainActor
final class PersistenceController: ObservableObject {
    @Published private(set) var modelContainer: ModelContainer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let schema = Schema([DownloadItem.self])

    var storeDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.appName, isDirectory: true)
    }

    var storeURL: URL {
        storeDirectoryURL.appendingPathComponent("Fetchora.sqlite")
    }

    init() {
        bootstrap()
    }

    func bootstrap() {
        isLoading = true

        do {
            modelContainer = try makeModelContainer()
            errorMessage = nil
        } catch {
            modelContainer = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func resetStore() {
        do {
            try backupAndRemoveStore()
            bootstrap()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openStoreFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([storeDirectoryURL])
    }

    private func makeModelContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        let config = ModelConfiguration(
            "Fetchora",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [config])
    }

    private func backupAndRemoveStore() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        let backupDirectory = storeDirectoryURL.appendingPathComponent(
            "Recovery-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            let destination = backupDirectory.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: url, to: destination)
        }
    }
}
