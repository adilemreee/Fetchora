import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.primaryGradient)
                .padding(.bottom, 16)

            Text("Welcome to Fetchora")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("The powerful Safari download manager for macOS")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 32)

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                step(number: 1, icon: "safari.fill", title: "Enable Safari Extension", description: "Safari → Develop → Allow Unsigned Extensions")
                step(number: 2, icon: "puzzlepiece.extension.fill", title: "Activate in Settings", description: "Safari → Settings → Extensions → Enable Fetchora")
                step(number: 3, icon: "arrow.down.doc.fill", title: "Start Downloading", description: "Click any download link in Safari — Fetchora handles the rest")
            }
            .padding(32)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)

            Spacer()

            Button(action: { hasCompleted = true }) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(Theme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surfacePrimary)
    }

    private func step(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(Theme.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }
}
