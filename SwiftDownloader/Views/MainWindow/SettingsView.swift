import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Constants.Keys.maxConcurrentDownloads) private var maxConcurrent = Constants.defaultMaxConcurrentDownloads
    @AppStorage(Constants.Keys.speedLimitPreset) private var speedLimitPreset = Constants.defaultSpeedLimitPreset
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
    @AppStorage(Constants.Keys.autoExtractArchives) private var autoExtractArchives = false
    @AppStorage(Constants.Keys.autoRemoveDeletedFiles) private var autoRemoveDeletedFiles = false
    @AppStorage(Constants.Keys.autoRemoveCompleted) private var autoRemoveCompleted = false
    @AppStorage(Constants.Keys.deleteConfirmation) private var deleteConfirmation = "ask"
    @State private var urlRules: [String] = SharedSettings.urlRules()
    @State private var newRuleDomain = ""
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

        var localizedName: String {
            switch self {
            case .general: return NSLocalizedString("settings.general", comment: "")
            case .downloads: return NSLocalizedString("settings.downloads", comment: "")
            case .appearance: return NSLocalizedString("settings.appearance", comment: "")
            case .network: return NSLocalizedString("settings.network", comment: "")
            case .advanced: return NSLocalizedString("settings.advanced", comment: "")
            case .about: return NSLocalizedString("settings.about", comment: "")
            }
        }

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
                                Text(tab.localizedName)
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
                            deleteConfirmationSection
                            clipboardSection
                            scheduledSection
                            urlRulesSection
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
        .onChange(of: maxConcurrent) { _, _ in
            DownloadManager.shared.refreshScheduling()
        }
        .onChange(of: speedLimitPreset) { _, _ in
            DownloadManager.shared.speedLimitConfigurationDidChange()
        }
        .onChange(of: customSpeedKBps) { _, _ in
            guard speedLimitPreset == "custom" else { return }
            DownloadManager.shared.speedLimitConfigurationDidChange()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(NSLocalizedString("settings.title", comment: ""))
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
        settingsSection(NSLocalizedString("settings.downloadLocation", comment: ""), icon: "folder.fill") {
            HStack {
                Text(downloadDirectory)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(NSLocalizedString("action.change", comment: "")) { chooseDirectory() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
            }
        }
    }

    private var performanceSection: some View {
        settingsSection(NSLocalizedString("settings.performance", comment: ""), icon: "gauge.high") {
            VStack(spacing: 16) {
                HStack {
                    Text(NSLocalizedString("settings.maxConcurrent", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: $maxConcurrent) {
                        ForEach(1...10, id: \.self) { i in Text("\(i)").tag(i) }
                    }
                    .frame(width: 80)
                }

                VStack(spacing: 10) {
                    HStack {
                        Text(NSLocalizedString("settings.speedLimit", comment: ""))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                    }

                    HStack(spacing: 0) {
                        speedPresetButton("low", label: NSLocalizedString("speedLimit.low", comment: ""), detail: "512 KB/s", color: .green, isFirst: true)
                        speedPresetButton("medium", label: NSLocalizedString("speedLimit.medium", comment: ""), detail: "2 MB/s", color: .orange)
                        speedPresetButton("high", label: NSLocalizedString("speedLimit.high", comment: ""), detail: NSLocalizedString("speedLimit.unlimited", comment: ""), color: .red)
                        speedPresetButton("custom", label: NSLocalizedString("speedLimit.custom", comment: ""), detail: customSpeedKBps > 0 ? "\(customSpeedKBps) KB/s" : "—", color: Theme.primary, isLast: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

                    if speedLimitPreset == "custom" {
                        HStack(spacing: 8) {
                            Text(NSLocalizedString("speedLimit.downloadSpeed", comment: ""))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            TextField("1024", value: $customSpeedKBps, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(size: 12, design: .monospaced))
                            Text("KB/s")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.textTertiary)
                        }
                        .padding(10)
                        .background(Theme.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    @AppStorage(Constants.Keys.speedLimitCustomKBps) private var customSpeedKBps = 1024

    private func speedPresetButton(_ preset: String, label: String, detail: String, color: Color, isFirst: Bool = false, isLast: Bool = false) -> some View {
        Button {
            withAnimation(Theme.quickAnimation) { speedLimitPreset = preset }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(speedLimitPreset == preset ? color : Theme.textTertiary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(speedLimitPreset == preset ? color.opacity(0.7) : Theme.textTertiary.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(speedLimitPreset == preset ? color.opacity(0.1) : Color.clear)
            .overlay(
                Group {
                    if !isFirst {
                        Rectangle().fill(Theme.border).frame(width: 1)
                    } else {
                        EmptyView()
                    }
                },
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
    }

    private var fileOrganizationSection: some View {
        settingsSection(NSLocalizedString("settings.fileOrganization", comment: ""), icon: "folder.badge.gearshape") {
            settingsToggle(isOn: $autoCategorize, title: NSLocalizedString("settings.autoCategorize", comment: ""), subtitle: NSLocalizedString("settings.autoCategorizeDesc", comment: ""))
        }
    }

    private var notificationsSection: some View {
        settingsSection(NSLocalizedString("settings.notifications", comment: ""), icon: "bell.fill") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $notificationsEnabled, title: NSLocalizedString("settings.desktopNotifications", comment: ""), subtitle: NSLocalizedString("settings.desktopNotificationsDesc", comment: ""))
                Divider().background(Theme.border)
                settingsToggle(isOn: $soundEnabled, title: NSLocalizedString("settings.soundAlerts", comment: ""), subtitle: NSLocalizedString("settings.soundAlertsDesc", comment: ""))
            }
        }
    }

    private var autoRetrySection: some View {
        settingsSection(NSLocalizedString("settings.autoRetry", comment: ""), icon: "arrow.clockwise") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $autoRetryEnabled, title: NSLocalizedString("settings.autoRetryTitle", comment: ""), subtitle: NSLocalizedString("settings.autoRetryDesc", comment: ""))

                if autoRetryEnabled {
                    Divider().background(Theme.border)
                    HStack {
                        Text(NSLocalizedString("settings.maxRetry", comment: ""))
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
        settingsSection(NSLocalizedString("settings.afterComplete", comment: ""), icon: "checkmark.circle.fill") {
            VStack(spacing: 14) {
                settingsPickerRow(title: NSLocalizedString("settings.actionLabel", comment: ""), selection: $completionAction, options: [
                    ("none", NSLocalizedString("settings.doNothing", comment: "")),
                    ("openFile", NSLocalizedString("settings.openFile", comment: "")),
                    ("openFolder", NSLocalizedString("settings.showInFinder", comment: ""))
                ])

                Divider().background(Theme.border)

                settingsToggle(isOn: $autoExtractArchives, title: NSLocalizedString("settings.autoExtract", comment: ""),
                               subtitle: NSLocalizedString("settings.autoExtractDesc", comment: ""))

                Divider().background(Theme.border)

                settingsToggle(isOn: $autoRemoveCompleted, title: NSLocalizedString("settings.autoRemoveCompleted", comment: ""),
                               subtitle: NSLocalizedString("settings.autoRemoveCompletedDesc", comment: ""))

                Divider().background(Theme.border)

                settingsToggle(isOn: $autoRemoveDeletedFiles, title: NSLocalizedString("settings.autoRemoveDeleted", comment: ""),
                               subtitle: NSLocalizedString("settings.autoRemoveDeletedDesc", comment: ""))
            }
        }
    }

    private var deleteConfirmationSection: some View {
        settingsSection(NSLocalizedString("settings.deleteConfirmation", comment: ""), icon: "trash.circle") {
            VStack(spacing: 14) {
                Text(NSLocalizedString("settings.deleteConfirmationDesc", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                settingsPickerRow(title: NSLocalizedString("settings.actionLabel", comment: ""), selection: $deleteConfirmation, options: [
                    ("ask", NSLocalizedString("settings.deleteAsk", comment: "")),
                    ("removeOnly", NSLocalizedString("settings.deleteRemoveOnly", comment: "")),
                    ("deleteFile", NSLocalizedString("settings.deleteAlsoFile", comment: ""))
                ])
            }
        }
    }

    private var themeSection: some View {
        settingsSection(NSLocalizedString("settings.theme", comment: ""), icon: "moon.fill") {
            HStack {
                Text(NSLocalizedString("settings.appearance", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Picker("", selection: $themeMode) {
                    Text(NSLocalizedString("settings.system", comment: "")).tag("system")
                    Text(NSLocalizedString("settings.dark", comment: "")).tag("dark")
                    Text(NSLocalizedString("settings.light", comment: "")).tag("light")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    private var clipboardSection: some View {
        settingsSection(NSLocalizedString("settings.clipboard", comment: ""), icon: "doc.on.clipboard") {
            settingsToggle(isOn: $clipboardMonitoring, title: NSLocalizedString("settings.monitorClipboard", comment: ""),
                           subtitle: NSLocalizedString("settings.monitorClipboardDesc", comment: ""))
                .onChange(of: clipboardMonitoring) { _, val in
                    if val { ClipboardMonitor.shared.startMonitoring() }
                    else { ClipboardMonitor.shared.stopMonitoring() }
                }
        }
    }

    private var scheduledSection: some View {
        settingsSection(NSLocalizedString("settings.scheduledDownloads", comment: ""), icon: "calendar.badge.clock") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $scheduledEnabled, title: NSLocalizedString("settings.enableScheduled", comment: ""),
                               subtitle: NSLocalizedString("settings.enableScheduledDesc", comment: ""))

                if scheduledEnabled {
                    Divider().background(Theme.border)
                    HStack {
                        Text(NSLocalizedString("settings.startAt", comment: ""))
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

    private var urlRulesSection: some View {
        settingsSection(NSLocalizedString("rules.title", comment: ""), icon: "link.badge.plus") {
            VStack(spacing: 14) {
                Text(NSLocalizedString("rules.description", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TextField(NSLocalizedString("rules.domainPlaceholder", comment: ""), text: $newRuleDomain)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button(NSLocalizedString("rules.addRule", comment: "")) {
                        addURLRule()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)
                    .disabled(newRuleDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if urlRules.isEmpty {
                    Text(NSLocalizedString("rules.noRules", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(urlRules, id: \.self) { rule in
                        HStack {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.primary)
                            Text(rule)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Button(action: { removeURLRule(rule) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.error)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func addURLRule() {
        let domain = URLRuleMatcher.normalize(newRuleDomain)
        guard !domain.isEmpty, !urlRules.contains(domain) else { return }
        urlRules.append(domain)
        UserDefaults.standard.set(urlRules, forKey: Constants.Keys.urlRules)
        SharedSettings.saveURLRules(urlRules)
        newRuleDomain = ""
    }

    private func removeURLRule(_ rule: String) {
        urlRules.removeAll { $0 == rule }
        UserDefaults.standard.set(urlRules, forKey: Constants.Keys.urlRules)
        SharedSettings.saveURLRules(urlRules)
    }

    private var appBehaviorSection: some View {
        settingsSection(NSLocalizedString("settings.appBehavior", comment: ""), icon: "gearshape.2.fill") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $launchAtLogin, title: NSLocalizedString("settings.launchAtLogin", comment: ""), subtitle: NSLocalizedString("settings.launchAtLoginDesc", comment: ""))
                    .onChange(of: launchAtLogin) { _, val in setLaunchAtLogin(val) }
                Divider().background(Theme.border)
                settingsToggle(isOn: $startMinimized, title: NSLocalizedString("settings.startMinimized", comment: ""), subtitle: NSLocalizedString("settings.startMinimizedDesc", comment: ""))
                Divider().background(Theme.border)
                settingsToggle(isOn: $hideFromDock, title: NSLocalizedString("settings.hideFromDock", comment: ""), subtitle: NSLocalizedString("settings.hideFromDockDesc", comment: ""))
                    .onChange(of: hideFromDock) { _, val in setHideFromDock(val) }
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection(NSLocalizedString("settings.appearance", comment: ""), icon: "paintbrush.fill") {
            settingsToggle(isOn: $showMenuBar, title: NSLocalizedString("settings.showMenuBar", comment: ""), subtitle: NSLocalizedString("settings.showMenuBarDesc", comment: ""))
        }
    }

    private var proxySection: some View {
        settingsSection(NSLocalizedString("settings.proxy", comment: ""), icon: "network") {
            VStack(spacing: 14) {
                settingsToggle(isOn: $proxyEnabled, title: NSLocalizedString("settings.useProxy", comment: ""), subtitle: NSLocalizedString("settings.useProxyDesc", comment: ""))

                if proxyEnabled {
                    Divider().background(Theme.border)

                    HStack {
                        Text(NSLocalizedString("settings.proxyType", comment: ""))
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
                        TextField(NSLocalizedString("settings.proxyHost", comment: ""), text: $proxyHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Text(":")
                            .foregroundColor(Theme.textTertiary)
                        TextField(NSLocalizedString("settings.proxyPort", comment: ""), text: $proxyPort)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(width: 60)
                    }

                    Divider().background(Theme.border)

                    Text(NSLocalizedString("settings.proxyAuth", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)

                    HStack(spacing: 8) {
                        TextField(NSLocalizedString("settings.proxyUsername", comment: ""), text: $proxyUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        SecureField(NSLocalizedString("settings.proxyPassword", comment: ""), text: $proxyPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    Button(NSLocalizedString("settings.testConnection", comment: "")) {
                        testProxyConnection()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .buttonStyle(.plain)

                    if let result = proxyTestResult {
                        HStack(spacing: 6) {
                            Image(systemName: result.contains("success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(result.contains("success") ? Theme.accent : Theme.error)
                            Text(result)
                                .font(.system(size: 12))
                                .foregroundColor(result.contains("success") ? Theme.accent : Theme.error)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((result.contains("success") ? Theme.accent : Theme.error).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    @State private var proxyTestResult: String? = nil

    private func testProxyConnection() {
        guard !proxyHost.isEmpty, let port = Int(proxyPort), port > 0 else {
            proxyTestResult = NSLocalizedString("settings.invalidHostPort", comment: "")
            return
        }
        proxyTestResult = nil
        let config = ProxySettings.configuredSessionConfiguration()
        let testSession = URLSession(configuration: config)
        let testURL = URL(string: "https://www.apple.com")!
        testSession.dataTask(with: testURL) { _, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.proxyTestResult = NSLocalizedString("settings.connectedSuccessfully", comment: "")
                } else {
                    self.proxyTestResult = error?.localizedDescription ?? NSLocalizedString("settings.connectionFailed", comment: "")
                }
            }
        }.resume()
    }

    private var safariExtensionSection: some View {
        settingsSection(NSLocalizedString("settings.safari", comment: ""), icon: "safari.fill") {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            Text(NSLocalizedString("settings.extensionInstalled", comment: ""))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Text(NSLocalizedString("settings.safariPath", comment: ""))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                    Button(NSLocalizedString("action.openSettings", comment: "")) {
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
        settingsSection(NSLocalizedString("settings.data", comment: ""), icon: "trash.fill") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("settings.clearAll", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                    Text(NSLocalizedString("settings.clearAllDesc", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button(NSLocalizedString("action.clearAll", comment: "")) {
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

                Text(NSLocalizedString("app.name", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text(String(format: NSLocalizedString("app.version", comment: ""), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)

            
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Info rows
            settingsSection(NSLocalizedString("about.title", comment: ""), icon: "info.circle") {
                VStack(spacing: 14) {
                    aboutRow(label: NSLocalizedString("about.developer", comment: ""), value: NSLocalizedString("about.developerName", comment: ""))
                    Divider().background(Theme.border)
                    aboutRow(label: NSLocalizedString("about.license", comment: ""), value: NSLocalizedString("about.licenseType", comment: ""))
                    Divider().background(Theme.border)
                    aboutRow(label: NSLocalizedString("about.platform", comment: ""), value: "macOS 14.0+")
                    Divider().background(Theme.border)
                    aboutRow(label: NSLocalizedString("about.framework", comment: ""), value: "SwiftUI + SwiftData")
                }
            }

            // Links
            settingsSection(NSLocalizedString("about.links", comment: ""), icon: "link") {
                VStack(spacing: 14) {
                    aboutLink(label: NSLocalizedString("about.website", comment: ""), icon: "globe", url: "https://adilemree.xyz")
                    Divider().background(Theme.border)
                    aboutLink(label: NSLocalizedString("about.privacyPolicy", comment: ""), icon: "hand.raised.fill", url: "https://adilemree.xyz/privacy")
                    Divider().background(Theme.border)
                    aboutLink(label: NSLocalizedString("about.support", comment: ""), icon: "questionmark.circle", url: "https://adilemree.xyz/support")
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
            if FileOrganizer.shared.setBaseDownloadDirectory(url) {
                downloadDirectory = FileOrganizer.shared.baseDownloadDirectory.path
            } else {
                downloadDirectory = url.path
            }
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
