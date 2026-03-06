import SafariServices

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey]

        guard let messageDict = message as? [String: Any],
              let action = messageDict["action"] as? String else {
            sendResponse(context: context, message: ["error": "Invalid message format"])
            return
        }

        switch action {
        case "newDownload":
            handleNewDownload(messageDict, context: context)
        case "openApp":
            handleOpenApp(context: context)
        case "getInterceptionConfig":
            handleGetInterceptionConfig(context: context)
        case "getStatus":
            sendResponse(context: context, message: ["status": "ok", "isRunning": isMainAppRunning])
        case "ping":
            sendResponse(context: context, message: ["status": "ok", "version": "1.0"])
        default:
            sendResponse(context: context, message: ["error": "Unknown action: \(action)"])
        }
    }

    private let appGroupIdentifier = "group.com.adilemre.SwiftDownloader"
    private let mainAppBundleIdentifier = "com.adilemre.SwiftDownloader"

    private var isMainAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: mainAppBundleIdentifier).isEmpty
    }

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func handleNewDownload(_ message: [String: Any], context: NSExtensionContext) {
        guard let url = message["url"] as? String else {
            sendResponse(context: context, message: ["error": "Missing URL"])
            return
        }

        let fileName = message["fileName"] as? String ?? URL(string: url)?.lastPathComponent ?? "download"

        if isMainAppRunning {
            // App Sandbox strips userInfo from DistributedNotifications.
            // Encode URL in the `object` parameter (which IS delivered).
            let payload = "\(url)|||SPLIT|||\(fileName)"

            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.adilemre.SwiftDownloader.newDownload"),
                object: payload,
                userInfo: nil,
                deliverImmediately: true
            )
        } else if var components = URLComponents(string: "fetchora://download") {
            components.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "fileName", value: fileName)
            ]

            if let launchURL = components.url {
                NSWorkspace.shared.open(launchURL)
            }
        }

        sendResponse(context: context, message: [
            "status": "success",
            "message": "Download started: \(fileName)"
        ])
    }

    private func handleOpenApp(context: NSExtensionContext) {
        // Post a distributed notification to wake up the main app
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.adilemre.SwiftDownloader.openApp"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // Also open via URL scheme as a fallback if the app isn't running
        if let url = URL(string: "fetchora://open") {
            NSWorkspace.shared.open(url)
        }

        sendResponse(context: context, message: ["status": "ok"])
    }

    private func handleGetInterceptionConfig(context: NSExtensionContext) {
        let urlRules = sharedDefaults?.stringArray(forKey: "urlRules") ?? []
        sendResponse(context: context, message: [
            "status": "ok",
            "urlRules": urlRules
        ])
    }

    private func sendResponse(context: NSExtensionContext, message: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: message]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
