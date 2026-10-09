import CryptoKit
import Foundation

/// What a backup is doing, for the window and the tool (brief §12).
public struct BackupProgress: Sendable {
    public enum Stage: String, Sendable { case scanning, copying, checking, finishing }
    public var stage: Stage
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var current: String?
}

public struct BackupResult: Sendable {
    public let manifest: Manifest
    /// The snapshot's folder: its name if verified, else `.incomplete-...`.
    public let folder: URL
    public var verified: Bool { manifest.status == .verified }
}

/// Backs up a source folder into a new snapshot (brief §6 steps 1-14;
/// B5, B7, B14): inventory, a new workspace, each file copied, hashed,
/// written sparse and read back, the source re-checked, the manifest
/// written and checked, and only then the snapshot given its name.
public struct SnapshotWriter: Sendable {
    public let repository: Repository
    /// For the tests only: called after each file is copied, to change the
    /// source mid-backup.
    var afterCopy: (@Sendable (Entry) -> Void)?

    public init(repository: Repository) { self.repository = repository }

    public func backup(_ source: URL, onProgress: @escaping @Sendable (BackupProgress) -> Void = { _ in })
        async throws -> BackupResult {
        let started = Date()
        let id = UUID()
        let name = Repository.snapshotName(started: started, id: id)
        try repository.prepare()

        onProgress(BackupProgress(stage: .scanning))
        let inventory = try Inventory.scan(source)
        let needed = inventory.totalBytes + 16 * 1_048_576
        if let free = repository.availableBytes, free < needed {
            throw BackupError.insufficientSpace(needed: needed, available: free)
        }

        let work = repository.workspace(for: id)
        let files = work.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        var entries = inventory.entries
        var warnings: [String] = []
        var progress = BackupProgress(stage: .copying, filesTotal: inventory.files.count,
                                      bytesTotal: inventory.totalBytes)
        var status = Manifest.Status.verified

        func finish(_ s: Manifest.Status) throws -> BackupResult {
            var m = manifest(id: id, name: name, status: s, started: started, source: source,
                             entries: entries, warnings: warnings)
            m.finished = Manifest.milliseconds(Date())
            try write(m, to: work)
            guard s == .verified else { return BackupResult(manifest: m, folder: work) }
            onProgress(BackupProgress(stage: .finishing))
            let final = repository.snapshots.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: final.path) else {
                m.status = .failed
                m.warnings.append(BackupError.snapshotExists(name).message)
                try write(m, to: work)
                return BackupResult(manifest: m, folder: work)
            }
            try FileManager.default.moveItem(at: work, to: final)
            return BackupResult(manifest: m, folder: final)
        }

        do {
            for i in entries.indices {
                try Task.checkCancellation()
                let e = entries[i]
                let from = source.appendingPathComponent(e.path)
                let to = files.appendingPathComponent(e.path)
                switch e.kind {
                case .folder:
                    try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                    entries[i].result = .verified
                case .link, .other:
                    entries[i].result = .skipped
                    entries[i].note = e.kind == .link ? "A symbolic link: not copied." : "Not a file or folder: not copied."
                    warnings.append("\(e.path): \(entries[i].note!)")
                case .file:
                    progress.current = e.path
                    onProgress(progress)
                    do {
                        let hash = try copy(from, to: to, expected: e)
                        entries[i].sha256 = hash
                        entries[i].result = .verified
                    } catch let error as CancellationError {
                        throw error
                    } catch let change as SourceChanged {
                        entries[i].result = .changed
                        entries[i].note = change.why
                        status = .inconsistent
                    } catch {
                        entries[i].result = .failed
                        entries[i].note = "\(error.localizedDescription)"
                        if status == .verified { status = .failed }
                    }
                    afterCopy?(entries[i])
                    progress.filesDone += 1
                    progress.bytesDone += e.size
                    onProgress(progress)
                }
            }

            // The source re-checked (B7): the same size, date and file as
            // before, and nothing gone.
            onProgress(BackupProgress(stage: .checking))
            // (Against the inventory itself: its dates at full precision.)
            for i in entries.indices where entries[i].kind == .file && entries[i].result == .verified {
                let before = inventory.entries[i]
                if let why = changed(before, in: source, id: inventory.fileIDs[before.path]) {
                    entries[i].result = .changed
                    entries[i].note = why
                    status = .inconsistent
                }
            }
            return try finish(status)
        } catch is CancellationError {
            return try finish(.cancelled)
        }
    }

    // MARK: Copying one file

    struct SourceChanged: Error { let why: String }

    static let zeros = Data(count: Hashing.chunk)

    /// Copies a file, hashing it as it's read; runs of zeros left as holes
    /// (B14); flushed, dated, then read back and checked. Its hash.
    func copy(_ from: URL, to: URL, expected: Entry) throws -> String {
        let input = try FileHandle(forReadingFrom: from)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: to.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: to.path])
        }
        let output = try FileHandle(forWritingTo: to)
        var hasher = SHA256()
        var offset: UInt64 = 0
        do {
            while let data = try input.read(upToCount: Hashing.chunk), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
                if data != SnapshotWriter.zeros.prefix(data.count) {
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
        guard Int64(offset) == expected.size else {
            throw SourceChanged(why: "It was \(expected.size) bytes when scanned, but \(offset) when copied.")
        }
        var dates: [FileAttributeKey: Any] = [:]
        if let m = expected.modified { dates[.modificationDate] = m }
        if let c = expected.created { dates[.creationDate] = c }
        if !dates.isEmpty { try? FileManager.default.setAttributes(dates, ofItemAtPath: to.path) }

        let hash = Hashing.hex(hasher.finalize())
        let back = try Hashing.sha256(of: to)
        guard back.size == expected.size, back.hash == hash else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
                "The copy doesn't match what was read from the card."])
        }
        return hash
    }

    /// Why a source file isn't the one inventoried, if it isn't.
    func changed(_ e: Entry, in source: URL, id: UInt64?) -> String? {
        let url = source.appendingPathComponent(e.path)
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileIdentifierKey]),
              FileManager.default.fileExists(atPath: url.path) else {
            return "It disappeared from the card during the backup."
        }
        if Int64(v.fileSize ?? -1) != e.size { return "Its size changed during the backup." }
        if v.contentModificationDate != e.modified { return "It was changed during the backup." }
        if let id, let now = v.fileIdentifier, now != id { return "It was replaced during the backup." }
        return nil
    }

    // MARK: The manifest

    func manifest(id: UUID, name: String, status: Manifest.Status, started: Date, source: URL,
                  entries: [Entry], warnings: [String]) -> Manifest {
        let v = try? source.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey,
                                                     .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey])
        // Dates to the millisecond, as the manifest keeps them, so the
        // manifest in memory is the one on disk.
        let entries = entries.map { e -> Entry in
            var e = e
            e.modified = e.modified.map(Manifest.milliseconds)
            e.created = e.created.map(Manifest.milliseconds)
            return e
        }
        let files = entries.filter { $0.kind == .file }
        return Manifest(schemaVersion: Manifest.schema, snapshotID: id, name: name, status: status,
                        started: Manifest.milliseconds(started), finished: Manifest.milliseconds(started),
                        app: .init(name: AppVersion.name, version: AppVersion.string),
                        source: .init(path: source.path, volumeName: v?.volumeName, volumeUUID: v?.volumeUUIDString,
                                      filesystem: v?.volumeLocalizedFormatDescription,
                                      capacity: v?.volumeTotalCapacity.map(Int64.init)),
                        totals: .init(files: files.count, folders: entries.filter { $0.kind == .folder }.count,
                                      bytes: files.reduce(0) { $0 + $1.size }),
                        entries: entries, warnings: warnings)
    }

    /// Written whole (atomically), then read back: it must be the same.
    func write(_ m: Manifest, to folder: URL) throws {
        let url = folder.appendingPathComponent(Manifest.fileName)
        try m.encoded().write(to: url, options: .atomic)
        let back = try Manifest.read(url)
        guard back.snapshotID == m.snapshotID, back.entries.map(\.sha256) == m.entries.map(\.sha256),
              back.status == m.status else {
            throw BackupError.manifestInvalid("it didn't read back as written")
        }
    }
}
