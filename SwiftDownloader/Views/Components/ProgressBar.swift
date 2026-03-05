import SwiftUI

struct ProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    var showPercentage: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.surfaceTertiary)

                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.progressGradient)
                    .frame(width: max(0, geometry.size.width * CGFloat(min(progress, 1.0))))
                    .animation(Theme.quickAnimation, value: progress)

                // Glow effect
                if progress > 0 && progress < 1 {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Theme.primary.opacity(0.4))
                        .frame(width: max(0, geometry.size.width * CGFloat(min(progress, 1.0))))
                        .blur(radius: 4)
                }
            }
        }
        .frame(height: height)
    }
}

struct SpeedBadge: View {
    let speed: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(speed.formattedSpeed)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceTertiary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundColor(Theme.primary)
    }
}

struct CategoryIcon: View {
    let category: FileCategory
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(Color(hex: category.color).opacity(0.15))
                .frame(width: size, height: size)

            Image(systemName: category.iconName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(Color(hex: category.color))
        }
    }
}

struct StatusBadge: View {
    let status: DownloadStatus

    var color: Color {
        switch status {
        case .downloading: return Theme.primary
        case .completed: return Theme.accent
        case .paused: return Theme.warning
        case .failed, .cancelled: return Theme.error
        case .waiting: return Theme.textTertiary
        case .scheduled: return Color(hex: "8B5CF6")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.localizedName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(Theme.textTertiary)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressBar(progress: 0.65)
        SpeedBadge(speed: 2_500_000)
        CategoryIcon(category: .video)
        StatusBadge(status: .downloading)
    }
    .padding()
    .background(Theme.surfacePrimary)
}
