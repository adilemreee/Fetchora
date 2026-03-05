import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Constants.Keys.maxConcurrentDownloads) private var maxConcurrent = Constants.defaultMaxConcurrentDownloads
    @AppStorage(Constants.Keys.speedLimitMBps) private var speedLimit = Constants.defaultSpeedLimitMBps
    @AppStorage(Constants.Keys.autoCategorizationEnabled) private var autoCategorize = Constants.defaultAutoCategorizationEnabled
    @AppStorage(Constants.Keys.showMenuBarIcon) private var showMenuBar = true
    @AppStorage(Constants.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Constants.Keys.startMinimized) private var startMinimized = false
    @AppStorage(Constants.Keys.hideFromDock) private var hideFromDock = false
    @AppStorage(Constants.Keys.soundEnabled) private var soundEnabled = true
    @AppStorage(Constants.Keys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(Constants.Keys.autoRetryEnabled) private var autoRetryEnabled = true
    @AppStorage(Constants.Keys.autoRetryCount) private var autoRetryCount = 3
    @AppStorage(Constants.Keys.completionAction) private var completionAction = "none"
    @AppStorage(Constants.Keys.proxyEnabled) private var proxyEnabled = false
    @AppStorage(Constants.Keys.proxyType) private var proxyType = "http"
    @AppStorage(Constants.Keys.proxyHost) private var proxyHost = ""
    @AppStorage(Constants.Keys.proxyPort) private var proxyPort = ""
    @AppStorage(Constants.Keys.proxyUsername) private var proxyUsername = ""
    @AppStorage(Constants.Keys.proxyPassword) private var proxyPassword = ""
    @AppStorage(Constants.Keys.clipboardMonitoring) private var clipboardMonitoring = false
    @AppStorage(Constants.Keys.themeMode) private var themeMode = "system"
    @AppStorage(Constants.Keys.scheduledDownloadEnabled) private var scheduledEnabled = false
    @AppStorage(Constants.Keys.scheduledDownloadHour) private var scheduledHour = 2
    @AppStorage(Constants.Keys.scheduledDownloadMinute) private var scheduledMinute = 0
    @State private var downloadDirectory: String = FileOrganizer.shared.baseDownloadDirectory.path
    @Environment(\.dismiss) private var dismiss

    @State private var settingsTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case downloads = "Downloads"
        case appearance = "Appearance"
        case network = "Network"
        case advanced = "Advanced"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .downloads: return "arrow.down.circle"
            case .appearance: return "paintbrush"
            case .network: return "network"
            case .advanced: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider().background(Theme.border)

            HStack(spacing: 0) {
                // Tab sidebar
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(Theme.quickAnimation) { settingsTab = tab }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(settingsTab == tab ? Theme.primary : Theme.textTertiary)
                                    .frame(width: 18)
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: settingsTab == tab ? .semibold : .regular))
                                    .foregroundColor(settingsTab == tab ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(settingsTab == tab ? Theme.primary.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 140)
                .padding(10)
                .background(Theme.surfaceSecondary)

                Divider().background(Theme.border)

                // Tab content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch settingsTab {
                        case .general:
                            downloadLocationSection
                            appBehaviorSection
                            safariExtensionSection
                        case .downloads:
                            performanceSection
                            fileOrganizationSection
                            autoRetrySection
                            completionActionSection
                            clipboardSection
                            scheduledSection
                        case .appearance:
                            themeSection
                            appearanceSection
                        case .network:
                            proxySection
                        case .advanced:
                            notificationsSection
                            dangerZoneSection
                        case .about:
                            aboutSection
                        }
                        Spacer(minLength: 16)
                    }
                    .padding(24)
                }
            }
        }
        .background(Theme.surfacePrimary)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Sections

    private var downloadLocationSection: some View {
        settingsSection("Download Location", icon: "folder.fill") {
            HStack {
                Text(downloadDirectory)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change") { chooseDirectory() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
            }
        }
    }

    private var performanceSection: some View {
        settingsSection("Performance", icon: "gauge.high") {
            VStack(spacing: 16) {
                HStack {
                    Text("Max Concurrent Downloads")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: $maxConcurrent) {
                        ForEach(1...10, id: \.self) { i in Text("\(i)").tag(i) }
                    }
                    .frame(width: 80)
                }

                HStack {
                    Text("Speed Limit")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        TextField("0", value: $speedLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("MB/s")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Text("Set to 0 for unlimited speed")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    private var fileOrganizationSection: some View {
        settingsSection("File Organization", icon: "folder.badge.gearshape") {
            settingsToggle(isOn: $autoCategorize, title: "Auto-categorize downloads", subtitle: "Sort files into category folders")
        }
    }

    private var notificationsSection: some View {
        settingsSection("Notifications", icon: "bell.fill") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $notificationsEnabled, title: "Desktop notifications", subtitle: "Show notification when download completes or fails")
                Divider().background(Theme.border)
                settingsToggle(isOn: $soundEnabled, title: "Sound alerts", subtitle: "Play sound when download completes")
            }
        }
    }

    private var autoRetrySection: some View {
        settingsSection("Auto Retry", icon: "arrow.clockwise") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $autoRetryEnabled, title: "Auto-retry failed downloads", subtitle: "Automatically retry when a download fails")

                if autoRetryEnabled {
                    Divider().background(Theme.border)
                    HStack {
                        Text("Max retry attempts")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: $autoRetryCount) {
                            ForEach(1...5, id: \.self) { i in Text("\(i)").tag(i) }
                        }
                        .frame(width: 60)
                    }
                }
            }
        }
    }

    private var completionActionSection: some View {
        settingsSection("After Download Completes", icon: "checkmark.circle.fill") {
            VStack(spacing: 14) {
                settingsPickerRow(title: "Action", selection: $completionAction, options: [
                    ("none", "Do nothing"),
                    ("openFile", "Open file"),
                    ("openFolder", "Show in Finder")
                ])
            }
        }
    }

    private var themeSection: some View {
        settingsSection("Theme", icon: "moon.fill") {
            HStack {
                Text("Appearance")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Picker("", selection: $themeMode) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    private var clipboardSection: some View {
        settingsSection("Clipboard", icon: "doc.on.clipboard") {
            settingsToggle(isOn: $clipboardMonitoring, title: "Monitor clipboard",
                           subtitle: "Auto-detect downloadable URLs from clipboard")
                .onChange(of: clipboardMonitoring) { _, val in
                    if val { ClipboardMonitor.shared.startMonitoring() }
                    else { ClipboardMonitor.shared.stopMonitoring() }
                }
        }
    }

    private var scheduledSection: some View {
        settingsSection("Scheduled Downloads", icon: "calendar.badge.clock") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $scheduledEnabled, title: "Enable scheduled downloads",
                               subtitle: "Queue downloads to start at a specific time")

                if scheduledEnabled {
                    Divider().background(Theme.border)
                    HStack {
                        Text("Start at")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: $scheduledHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 60)
                        Text(":")
                            .foregroundColor(Theme.textTertiary)
                        Picker("", selection: $scheduledMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .frame(width: 60)
                    }
                }
            }
        }
    }

    private var appBehaviorSection: some View {
        settingsSection("App Behavior", icon: "gearshape.2.fill") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $launchAtLogin, title: "Launch at login", subtitle: "Start when you log in")
                    .onChange(of: launchAtLogin) { _, val in setLaunchAtLogin(val) }
                Divider().background(Theme.border)
                settingsToggle(isOn: $startMinimized, title: "Start minimized", subtitle: "Only show menu bar on launch")
                Divider().background(Theme.border)
                settingsToggle(isOn: $hideFromDock, title: "Hide from Dock", subtitle: "Requires restart")
                    .onChange(of: hideFromDock) { _, val in setHideFromDock(val) }
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection("Appearance", icon: "paintbrush.fill") {
            settingsToggle(isOn: $showMenuBar, title: "Show menu bar icon", subtitle: "Quick access from status bar")
        }
    }

    private var proxySection: some View {
        settingsSection("Proxy", icon: "network") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $proxyEnabled, title: "Use proxy", subtitle: "Route downloads through a proxy server")

                if proxyEnabled {
                    Divider().background(Theme.border)

                    HStack {
                        Text("Type")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: $proxyType) {
                            Text("HTTP").tag("http")
                            Text("SOCKS5").tag("socks5")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    HStack(spacing: 8) {
                        TextField("Host (e.g. 127.0.0.1)", text: $proxyHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Text(":")
                            .foregroundColor(Theme.textTertiary)
                        TextField("Port", text: $proxyPort)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(width: 60)
                    }

                    Divider().background(Theme.border)

                    Text("Authentication (optional)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)

                    HStack(spacing: 8) {
                        TextField("Username", text: $proxyUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        SecureField("Password", text: $proxyPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    Button("Test Connection") {
                        testProxyConnection()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @State private var proxyTestResult: String? = nil

    private func testProxyConnection() {
        guard !proxyHost.isEmpty, let port = Int(proxyPort), port > 0 else {
            proxyTestResult = "Invalid host or port"
            return
        }
        proxyTestResult = nil
        let config = ProxySettings.configuredSessionConfiguration()
        let testSession = URLSession(configuration: config)
        let testURL = URL(string: "https://www.apple.com")!
        testSession.dataTask(with: testURL) { _, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.proxyTestResult = "Connected successfully"
                } else {
                    self.proxyTestResult = error?.localizedDescription ?? "Connection failed"
                }
            }
        }.resume()
    }

    private var safariExtensionSection: some View {
        settingsSection("Safari Extension", icon: "safari.fill") {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            Text("Extension Installed")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Text("Safari → Settings → Extensions → Fetchora")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Safari.Extensions")!)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        settingsSection("Data", icon: "trash.fill") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear all downloads")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                    Text("Remove all download records")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button("Clear") {
                    NotificationCenter.default.post(name: Notification.Name("clearAllDownloads"), object: nil)
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.error)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        VStack(spacing: 20) {
            // App identity
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.primaryGradient)

                Text("Fetchora")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)

            
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Info rows
            settingsSection("Info", icon: "info.circle") {
                VStack(spacing: 14) {
                    aboutRow(label: "Developer", value: "Adil Emre")
                    Divider().background(Theme.border)
                    aboutRow(label: "License", value: "All Rights Reserved")
                    Divider().background(Theme.border)
                    aboutRow(label: "Platform", value: "macOS 14.0+")
                    Divider().background(Theme.border)
                    aboutRow(label: "Framework", value: "SwiftUI + SwiftData")
                }
            }

            // Links
            settingsSection("Links", icon: "link") {
                VStack(spacing: 14) {
                    aboutLink(label: "Website", icon: "globe", url: "https://adilemree.xyz")
                    Divider().background(Theme.border)
                    aboutLink(label: "Privacy Policy", icon: "hand.raised.fill", url: "https://adilemree.xyz/privacy")
                    Divider().background(Theme.border)
                    aboutLink(label: "Support", icon: "questionmark.circle", url: "https://adilemree.xyz/support")
                }
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private func aboutLink(label: String, icon: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.primary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.primary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    private func settingsToggle(isOn: Binding<Bool>, title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(Theme.primary)
                .labelsHidden()
        }
    }

    private func settingsPickerRow(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .frame(width: 160)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url.path
            UserDefaults.standard.set(url.path, forKey: Constants.Keys.downloadDirectory)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { print("Launch at login error: \(error)") }
    }

    private func setHideFromDock(_ hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}
