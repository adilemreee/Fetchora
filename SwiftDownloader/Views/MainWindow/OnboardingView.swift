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

            Text(NSLocalizedString("onboarding.welcome", comment: ""))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(NSLocalizedString("onboarding.subtitle", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 32)

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                step(number: 1, icon: "safari.fill", title: NSLocalizedString("onboarding.step1.title", comment: ""), description: NSLocalizedString("onboarding.step1.description", comment: ""))
                step(number: 2, icon: "puzzlepiece.extension.fill", title: NSLocalizedString("onboarding.step2.title", comment: ""), description: NSLocalizedString("onboarding.step2.description", comment: ""))
                step(number: 3, icon: "arrow.down.doc.fill", title: NSLocalizedString("onboarding.step3.title", comment: ""), description: NSLocalizedString("onboarding.step3.description", comment: ""))
            }
            .padding(32)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)

            Spacer()

            Button(action: { hasCompleted = true }) {
                Text(NSLocalizedString("onboarding.getStarted", comment: ""))
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
