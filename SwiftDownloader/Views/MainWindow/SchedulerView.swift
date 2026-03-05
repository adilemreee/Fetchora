import SwiftUI

struct SchedulerView: View {
    @ObservedObject var scheduler = SchedulerService.shared
    @State private var showAddSheet = false
    @State private var newURL = ""
    @State private var newDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduler")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Schedule downloads for later")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()

                Button(action: { showAddSheet = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Schedule")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().background(Theme.border)

            if scheduler.scheduledItems.isEmpty {
                EmptyStateView(
                    icon: "calendar.circle",
                    title: "No Scheduled Downloads",
                    subtitle: "Add downloads to run at a specific time"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(scheduler.scheduledItems) { schedule in
                            scheduleRow(schedule)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.surfacePrimary)
        .sheet(isPresented: $showAddSheet) {
            addScheduleSheet
        }
    }

    // MARK: - Schedule Row

    private func scheduleRow(_ schedule: DownloadSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(schedule.isEnabled ? Color(hex: "8B5CF6") : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.scheduledDate.shortFormatted)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                if schedule.isRecurring, let interval = schedule.repeatInterval {
                    Text("Repeats \(interval.rawValue.lowercased())")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { _ in scheduler.toggleSchedule(id: schedule.id) }
            ))
            .toggleStyle(.switch)
            .tint(Color(hex: "8B5CF6"))

            Button(action: { scheduler.removeSchedule(for: schedule.downloadId) }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.error)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    // MARK: - Add Sheet

    private var addScheduleSheet: some View {
        VStack(spacing: 20) {
            Text("Schedule Download")
                .font(.system(size: 16, weight: .bold))

            TextField("Download URL", text: $newURL)
                .textFieldStyle(.roundedBorder)

            DatePicker("Start at", selection: $newDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Button("Cancel") { showAddSheet = false }
                    .buttonStyle(.plain)

                Spacer()

                Button("Schedule") {
                    addScheduledDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newURL.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func addScheduledDownload() {
        guard let url = URL(string: newURL) else { return }
        let fileName = url.lastPathComponent
        let destination = FileOrganizer.shared.destinationURL(for: fileName)
        let downloadId = UUID()

        scheduler.schedule(downloadId: downloadId, at: newDate)

        newURL = ""
        newDate = Date()
        showAddSheet = false
    }
}
