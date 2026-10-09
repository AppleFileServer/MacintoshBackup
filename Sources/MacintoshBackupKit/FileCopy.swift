import CryptoKit
import Foundation

/// One file copied safely (B7, B14): read in chunks and hashed as it's
/// read; runs of zeros left as holes; flushed; dated; read back and
/// checked. Used for backing up and for restoring.
enum FileCopy {
    struct SizeChanged: Error { let why: String }

    static let zeros = Data(count: Hashing.chunk)

    /// The SHA-256 of what was read. `to` must not exist.
    static func copy(_ from: URL, to: URL, size: Int64, modified: Date?, created: Date?) throws -> String {
        let input = try FileHandle(forReadingFrom: from)
        defer { try? input.close() }
        guard !FileManager.default.fileExists(atPath: to.path),
              FileManager.default.createFile(atPath: to.path, contents: nil) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: to.path])
        }
        let output = try FileHandle(forWritingTo: to)
        var hasher = SHA256()
        var offset: UInt64 = 0
        do {
            while let data = try input.read(upToCount: Hashing.chunk), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
                if data != zeros.prefix(data.count) {
                    try output.seek(toOffset: offset)
                    try output.write(contentsOf: data)
                }
                offset += UInt64(data.count)
            }
            try output.truncate(atOffset: offset)
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        guard Int64(offset) == size else {
            throw SizeChanged(why: "It was \(size) bytes when scanned, but \(offset) when copied.")
        }
        var dates: [FileAttributeKey: Any] = [:]
        if let modified { dates[.modificationDate] = modified }
        if let created { dates[.creationDate] = created }
        if !dates.isEmpty { try? FileManager.default.setAttributes(dates, ofItemAtPath: to.path) }
        let hash = Hashing.hex(hasher.finalize())
        let back = try Hashing.sha256(of: to)
        guard back.size == size, back.hash == hash else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
                "The copy doesn't match what was read."])
        }
        return hash
    }
}
