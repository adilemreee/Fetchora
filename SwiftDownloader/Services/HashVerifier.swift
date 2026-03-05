import Foundation
import CryptoKit

enum HashType: String, CaseIterable {
    case md5 = "MD5"
    case sha256 = "SHA-256"
}

class HashVerifier {
    private static let chunkSize = 4 * 1024 * 1024 // 4 MB

    static func verify(fileAt url: URL, expectedHash: String, type: HashType) async -> (matches: Bool, computed: String) {
        guard let computed = await computeHash(fileAt: url, type: type) else {
            return (false, "Error reading file")
        }
        return (computed.lowercased() == expectedHash.lowercased(), computed)
    }

    static func computeHash(fileAt url: URL, type: HashType) async -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        switch type {
        case .md5:
            var hasher = Insecure.MD5()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
        case .sha256:
            var hasher = SHA256()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
        }
    }
}
