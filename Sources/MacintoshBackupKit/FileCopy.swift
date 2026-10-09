import CryptoKit
import Foundation

/// One file copied safely (B7, B14): read in chunks and hashed as it's
/// read; runs of zeros left as holes; flushed; dated; read back and
/// checked. Used for backing up and for restoring.
enum FileCopy {
    struct SizeChanged: Error { let why: String }

    /// A restore's hidden temporary file, ".mbu-restore-<UUID>" (F4).
    static func isLeftover(_ name: String) -> Bool {
        name.wholeMatch(of: /\.mbu-restore-[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/) != nil
    }

    /// Removes an interrupted restore's temporary files from `folder` (F4):
    /// only files with that exact name, only in that folder.
    static func removeLeftovers(in folder: URL) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where isLeftover(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    static let zeros = Data(count: Hashing.chunk)

    /// The SHA-256 of what was read. `to` must not exist.
    /// `sparse` false writes every byte (for a card: FAT has no holes, and
    /// one plain write keeps an image in one piece).
    static func copy(_ from: URL, to: URL, size: Int64, modified: Date?, created: Date?, sparse: Bool = true) throws -> String {
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
            while true {
                // Each chunk's memory released as it goes (F1).
                let more: Bool = try autoreleasepool {
                    guard let data = try input.read(upToCount: Hashing.chunk), !data.isEmpty else { return false }
                    hasher.update(data: data)
                    if !sparse || data != zeros.prefix(data.count) {
                        try output.seek(toOffset: offset)
                        try output.write(contentsOf: data)
                    }
                    offset += UInt64(data.count)
                    return true
                }
                guard more else { break }
                try Task.checkCancellation()
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
