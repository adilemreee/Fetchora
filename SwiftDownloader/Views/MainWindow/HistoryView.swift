import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DownloadItem.dateAdded, order: .reverse)
    private var allItems: [DownloadItem]

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var historyItems: [DownloadItem] {
        allItems.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    private var filteredItems: [DownloadItem] {
        guard !searchText.isEmpty else { return historyItems }
        return historyItems.filter { $0.fileName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            searchSection
            Divider().background(Theme.border)
            listSection
        }
        .background(Theme.surfacePrimary)
    }

    private var headerSection: some View {
        HStack {
            Text("Download History")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            if !historyItems.isEmpty {
                Button("Clear History") {
                    clearHistory()
                }
                .font(.system(size: 12))
                .foregroundColor(Theme.error)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textTertiary)
            TextField("Search history...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var listSection: some View {
        if filteredItems.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No History",
                subtitle: "Your download history will appear here"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredItems) { item in
                        DownloadRowView(item: item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private func clearHistory() {
        for item in historyItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}
