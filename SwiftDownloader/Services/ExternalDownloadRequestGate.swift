import Foundation

@MainActor
final class ExternalDownloadRequestGate {
    static let shared = ExternalDownloadRequestGate()

    private var recentRequests: [String: Date] = [:]
    private let duplicateWindow: TimeInterval = 1.5

    private init() {}

    func shouldForward(urlString: String, fileName: String, now: Date = Date()) -> Bool {
        recentRequests = recentRequests.filter { now.timeIntervalSince($0.value) < duplicateWindow }

        let key = requestKey(urlString: urlString, fileName: fileName)
        if let lastSeenAt = recentRequests[key], now.timeIntervalSince(lastSeenAt) < duplicateWindow {
            return false
        }

        recentRequests[key] = now
        return true
    }

    private func requestKey(urlString: String, fileName: String) -> String {
        let normalizedURL = DuplicateDownloadResolver.normalizedURLString(urlString) ?? urlString
        let normalizedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedURL)|||\(normalizedFileName)"
    }
}
