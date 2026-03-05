import Foundation
import CryptoKit

enum HashType: String, CaseIterable {
    case md5 = "MD5"
    case sha256 = "SHA-256"
}

class HashVerifier {
    static func verify(fileAt url: URL, expectedHash: String, type: HashType) async -> (matches: Bool, computed: String) {
        guard let data = try? Data(contentsOf: url) else {
            return (false, "Error reading file")
        }

        let computed: String
        switch type {
        case .md5:
            computed = Insecure.MD5.hash(data: data)
                .map { String(format: "%02hhx", $0) }
                .joined()
        case .sha256:
            computed = SHA256.hash(data: data)
                .map { String(format: "%02hhx", $0) }
                .joined()
        }

        return (computed.lowercased() == expectedHash.lowercased(), computed)
    }

    static func computeHash(fileAt url: URL, type: HashType) async -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        switch type {
        case .md5:
            return Insecure.MD5.hash(data: data)
                .map { String(format: "%02hhx", $0) }
                .joined()
        case .sha256:
            return SHA256.hash(data: data)
                .map { String(format: "%02hhx", $0) }
                .joined()
        }
    }
}
