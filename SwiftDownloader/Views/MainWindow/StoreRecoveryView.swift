import SwiftUI

struct StoreRecoveryView: View {
    @ObservedObject var persistenceController: PersistenceController
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: compact ? 20 : 28))
                    .foregroundColor(Theme.warning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("storeRecovery.title", comment: ""))
                        .font(.system(size: compact ? 14 : 22, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Text(NSLocalizedString("storeRecovery.subtitle", comment: ""))
                        .font(.system(size: compact ? 11 : 13))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("storeRecovery.errorLabel", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)

                Text(persistenceController.errorMessage ?? NSLocalizedString("storeRecovery.unknownError", comment: ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(compact ? 12 : 14)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            Text(NSLocalizedString("storeRecovery.resetDescription", comment: ""))
                .font(.system(size: compact ? 11 : 12))
                .foregroundColor(Theme.textTertiary)

            HStack(spacing: 10) {
                Button(NSLocalizedString("storeRecovery.tryAgain", comment: "")) {
                    persistenceController.bootstrap()
                }
                .buttonStyle(.borderedProminent)

                Button(NSLocalizedString("storeRecovery.resetStore", comment: "")) {
                    persistenceController.resetStore()
                }
                .buttonStyle(.bordered)

                Button(NSLocalizedString("storeRecovery.openFolder", comment: "")) {
                    persistenceController.openStoreFolder()
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.primary)
            }
        }
        .padding(compact ? 16 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfacePrimary)
    }
}
