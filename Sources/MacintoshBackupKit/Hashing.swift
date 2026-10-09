import CryptoKit
import Foundation

/// SHA-256 a chunk at a time (brief §7): a 2 GB image never sits in memory.
enum Hashing {
    static let chunk = 1 << 20

    static func hex<D: Digest>(_ d: D) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// The file's SHA-256 and length, read from the start.
    static func sha256(of url: URL) throws -> (hash: String, size: Int64) {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        // Each chunk's memory released as it goes (F1: without the pool, a
        // 3 GB image took 2 GB of memory).
        while true {
            let more: Bool = try autoreleasepool {
                guard let data = try h.read(upToCount: chunk), !data.isEmpty else { return false }
                hasher.update(data: data)
                size += Int64(data.count)
                return true
            }
            guard more else { break }
            try Task.checkCancellation()
        }
        return (hex(hasher.finalize()), size)
    }
}
