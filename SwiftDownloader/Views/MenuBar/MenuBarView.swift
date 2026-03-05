import SwiftUI
import SwiftData

struct MiniDownloadRow: View {
    @Bindable var item: DownloadItem
    @ObservedObject var downloadManager = DownloadManager.shared

    private var speed: Double { downloadManager.speeds[item.id] ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: item.category, size: 28)
            fileInfoSection
            Spacer()
            quickActionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            if item.status == .downloading || item.status == .paused {
                ProgressBar(progress: item.progress, height: 3)
            }

            HStack(spacing: 6) {
                if item.status == .downloading {
                    Text(speed.formattedSpeed)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.primary)
                }

                Text(item.progressPercentage)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var quickActionButton: some View {
        if item.status == .downloading {
            Button(action: { downloadManager.pauseDownload(item: item) }) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.warning)
                    .frame(width: 22, height: 22)
                    .background(Theme.warning.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        } else if item.status == .paused {
            Button(action: { downloadManager.resumeDownload(item: item, force: true) }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct MenuBarView: View {
    @Query(sort: \DownloadItem.dateAdded, order: .reverse)
    private var allItems: [DownloadItem]

    @ObservedObject var downloadManager = DownloadManager.shared
    @Environment(\.openWindow) private var openWindow

    private var activeItems: [DownloadItem] {
        allItems.filter { $0.status == .downloading || $0.status == .paused || $0.status == .waiting }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().background(Theme.border)
            downloadListSection
            Divider().background(Theme.border)
            footerSection
        }
        .frame(width: Theme.menuBarWidth)
        .background(Theme.surfacePrimary)
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.primaryGradient)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("app.name", comment: ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                if !activeItems.isEmpty {
                    Text(String(format: NSLocalizedString("menubar.activeCount", comment: ""), activeItems.count) + " · " + downloadManager.totalSpeed.formattedSpeed)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
            }

            Spacer()

            if downloadManager.totalSpeed > 0 {
                SpeedBadge(speed: downloadManager.totalSpeed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var downloadListSection: some View {
        if activeItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(Theme.accent)
                Text(NSLocalizedString("menuBar.noActive", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(activeItems) { item in
                        MiniDownloadRow(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        }
    }

    private var footerSection: some View {
        HStack(spacing: 16) {
            if !activeItems.isEmpty {
                Button(NSLocalizedString("action.pauseAll", comment: "")) {
                    downloadManager.pauseAll()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.warning)
                .buttonStyle(.plain)

                if activeItems.contains(where: { $0.status == .paused }) {
                    Button(NSLocalizedString("action.resumeAll", comment: "")) {
                        downloadManager.resumeAll(items: activeItems)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button(NSLocalizedString("menuBar.openApp", comment: "")) {
                if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                    window.makeKeyAndOrderFront(nil)
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
