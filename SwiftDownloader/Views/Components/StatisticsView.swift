import SwiftUI
import SwiftData

struct StatisticsView: View {
    @Query private var allItems: [DownloadItem]

    private var totalDownloaded: Int64 {
        allItems.filter { $0.status == .completed }.reduce(0) { $0 + $1.totalBytes }
    }

    private var completedCount: Int {
        allItems.filter { $0.status == .completed }.count
    }

    private var failedCount: Int {
        allItems.filter { $0.status == .failed }.count
    }

    private var categoryStats: [(FileCategory, Int)] {
        var counts: [FileCategory: Int] = [:]
        for item in allItems where item.status == .completed {
            counts[item.category, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            // Stats grid
            HStack(spacing: 12) {
                statCard(title: "Downloaded", value: totalDownloaded.formattedFileSize, icon: "arrow.down.circle", color: Theme.primary)
                statCard(title: "Completed", value: "\(completedCount)", icon: "checkmark.circle", color: Theme.accent)
                statCard(title: "Failed", value: "\(failedCount)", icon: "xmark.circle", color: Theme.error)
            }

            // Category breakdown
            if !categoryStats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Category")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)

                    ForEach(categoryStats.prefix(5), id: \.0) { category, count in
                        HStack(spacing: 8) {
                            CategoryIcon(category: category, size: 20)
                            Text(category.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
