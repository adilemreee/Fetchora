import Foundation
import SwiftData

@MainActor
struct PreviewHelper {

    static func populateDemoData(context: ModelContext) {
        // Clear existing items first
        let descriptor = FetchDescriptor<DownloadItem>()
        if let existing = try? context.fetch(descriptor) {
            for item in existing { context.delete(item) }
        }

        let downloads = "/Users/\(NSUserName())/Downloads"

        let demoItems: [(String, String, FileCategory, DownloadStatus, DownloadPriority, Int64, Int64, Int)] = [
            // Actively downloading - big video file
            ("https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso",
             "ubuntu-24.04-desktop-amd64.iso", .archive, .downloading, .high,
             4_700_000_000, 2_350_000_000, -1),

            // Downloading - movie
            ("https://media.example.com/files/The_Great_Gatsby_2024_4K.mkv",
             "The_Great_Gatsby_2024_4K.mkv", .video, .downloading, .normal,
             8_500_000_000, 6_120_000_000, -2),

            // Paused
            ("https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg",
             "googlechrome.dmg", .application, .paused, .low,
             245_000_000, 98_000_000, -5),

            // Completed items
            ("https://nodejs.org/dist/v22.0.0/node-v22.0.0.pkg",
             "node-v22.0.0.pkg", .application, .completed, .normal,
             82_500_000, 82_500_000, -60),

            ("https://files.example.com/music/Ludovico_Einaudi_Experience.flac",
             "Ludovico_Einaudi_Experience.flac", .audio, .completed, .normal,
             45_200_000, 45_200_000, -120),

            ("https://images.unsplash.com/photo-2024-wallpaper-5K.png",
             "wallpaper-5K-mountains.png", .image, .completed, .normal,
             18_900_000, 18_900_000, -180),

            ("https://developer.apple.com/docs/SwiftUI-Documentation.pdf",
             "SwiftUI-Documentation.pdf", .document, .completed, .normal,
             12_400_000, 12_400_000, -300),

            ("https://github.com/user/project/archive/refs/heads/main.zip",
             "swift-project-main.zip", .archive, .completed, .normal,
             5_600_000, 5_600_000, -400),

            ("https://cdn.example.com/fonts/SF-Pro-Display.zip",
             "SF-Pro-Display.zip", .archive, .completed, .normal,
             8_100_000, 8_100_000, -500),

            ("https://releases.example.com/app/Sketch-99.dmg",
             "Sketch-99.dmg", .application, .completed, .high,
             78_000_000, 78_000_000, -600),

            // Waiting
            ("https://dl.example.com/video/WWDC25-Keynote.mp4",
             "WWDC25-Keynote.mp4", .video, .waiting, .normal,
             2_100_000_000, 0, -3),

            // Scheduled
            ("https://releases.example.com/blender/blender-4.2-macos-arm64.dmg",
             "blender-4.2-macos-arm64.dmg", .application, .scheduled, .normal,
             450_000_000, 0, 0),
        ]

        for (i, demo) in demoItems.enumerated() {
            let item = DownloadItem(
                url: demo.0,
                fileName: demo.1,
                destinationPath: "\(downloads)/\(demo.1)",
                category: demo.2,
                priority: demo.4
            )
            item.status = demo.3
            item.totalBytes = demo.5
            item.downloadedBytes = demo.6
            item.dateAdded = Date().addingTimeInterval(TimeInterval(demo.7 * 60))

            if demo.3 == .completed {
                item.dateCompleted = item.dateAdded.addingTimeInterval(120)
            }
            if demo.3 == .scheduled {
                item.scheduledDate = Date().addingTimeInterval(3600 * 3)
            }

            context.insert(item)

            // Inject fake speeds for active downloads
            if demo.3 == .downloading {
                let speed: Double = i == 0 ? 15_400_000 : 8_700_000 // ~15.4 MB/s, ~8.7 MB/s
                DownloadManager.shared.speeds[item.id] = speed
                let remaining = Double(demo.5 - demo.6)
                DownloadManager.shared.etas[item.id] = remaining / speed
            }
        }

        try? context.save()
    }

    static func clearDemoData(context: ModelContext) {
        let descriptor = FetchDescriptor<DownloadItem>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                DownloadManager.shared.speeds.removeValue(forKey: item.id)
                DownloadManager.shared.etas.removeValue(forKey: item.id)
                context.delete(item)
            }
            try? context.save()
        }
    }
}
