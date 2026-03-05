import Foundation
import UserNotifications
import AppKit

class NotificationService {
    static let shared = NotificationService()

    private init() {
        requestPermission()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[Notifications] Permission error: \(error)")
            }
        }
    }

    func showDownloadComplete(fileName: String, path: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = fileName
        content.sound = UserDefaults.standard.bool(forKey: Constants.Keys.soundEnabled)
            ? .default
            : nil
        content.userInfo = ["filePath": path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func showDownloadFailed(fileName: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = "\(fileName): \(error)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func playCompletionSound() {
        guard UserDefaults.standard.bool(forKey: Constants.Keys.soundEnabled) else { return }
        NSSound(named: .init("Glass"))?.play()
    }
}
