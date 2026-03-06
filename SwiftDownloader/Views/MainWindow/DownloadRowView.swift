import SwiftUI
import SwiftData

struct DownloadRowView: View {
    @Bindable var item: DownloadItem
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isHovered = false
    var onDelete: (() -> Void)?

    private var speed: Double {
        downloadManager.speeds[item.id] ?? 0
    }

    private var eta: TimeInterval {
        downloadManager.etas[item.id] ?? .infinity
    }

    var body: some View {
        HStack(spacing: 14) {
            // Category Icon with delete overlay on hover
            ZStack(alignment: .topLeading) {
                CategoryIcon(category: item.category, size: 40)

                if isHovered, let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.error)
                            .background(Circle().fill(Theme.surfacePrimary).frame(width: 14, height: 14))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
            }

            // File Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if item.safePriority != .normal {
                        Text(item.safePriority.localizedName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(item.safePriority == .high ? Theme.error : Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background((item.safePriority == .high ? Theme.error : Theme.accent).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    StatusBadge(status: item.status)

                    if item.status == .completed && !item.fileExists {
                        Text(NSLocalizedString("status.fileDeleted", comment: ""))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.error)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.error.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Progress Bar
                if item.status == .downloading || item.status == .paused || item.status == .waiting {
                    ProgressBar(progress: item.progress, height: 5)
                }

                // Bottom info
                HStack(spacing: 12) {
                    // File size
                    if item.totalBytes > 0 {
                        Text("\(item.downloadedBytes.formattedFileSize) / \(item.totalBytes.formattedFileSize)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.none, value: item.downloadedBytes)
                    }

                    // Speed
                    if item.status == .downloading && speed > 0 {
                        SpeedBadge(speed: speed)
                    }

                    Spacer()

                    // ETA
                    if item.status == .downloading && !eta.isInfinite {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(eta.formattedETA)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(Theme.textTertiary)
                    }

                    // Percentage
                    if item.status == .downloading || item.status == .paused {
                        Text(item.progressPercentage)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.primary)
                    }

                    // Completed date
                    if item.status == .completed, let date = item.dateCompleted {
                        Text(date.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }

                    // Scheduled date
                    if item.status == .scheduled, let date = item.scheduledDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 10))
                            Text(date, style: .time)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.accent)
                    }

                    // Added date for idle items
                    if item.status == .waiting || item.status == .failed || item.status == .cancelled {
                        Text(item.dateAdded.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }

            if isHovered {
                actionButtons
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(isHovered ? Theme.surfaceTertiary.opacity(0.6) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(Theme.quickAnimation) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            switch item.status {
            case .downloading:
                actionButton(icon: "pause.fill", color: Theme.warning) {
                    downloadManager.pauseDownload(item: item)
                }
                actionButton(icon: "xmark", color: Theme.error) {
                    downloadManager.cancelDownload(item: item)
                }
            case .paused:
                actionButton(icon: "play.fill", color: Theme.accent) {
                    downloadManager.resumeDownload(item: item, force: true)
                }
                actionButton(icon: "xmark", color: Theme.error) {
                    downloadManager.cancelDownload(item: item)
                }
            case .waiting:
                actionButton(icon: "play.fill", color: Theme.accent) {
                    downloadManager.forceStartDownload(item: item)
                }
                actionButton(icon: "xmark", color: Theme.error) {
                    downloadManager.cancelDownload(item: item)
                }
            case .failed, .cancelled:
                actionButton(icon: "arrow.clockwise", color: Theme.primary) {
                    downloadManager.retryDownload(item: item)
                }
            case .completed:
                actionButton(icon: "folder", color: Theme.textSecondary) {
                    revealInFinder()
                }
            case .scheduled:
                actionButton(icon: "play.fill", color: Theme.accent) {
                    downloadManager.startDownload(item: item)
                }
            }
        }
    }

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: item.destinationPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
