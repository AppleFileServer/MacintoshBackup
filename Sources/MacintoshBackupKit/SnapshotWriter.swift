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

    public init(stage: Stage, filesDone: Int = 0, filesTotal: Int = 0, bytesDone: Int64 = 0,
                bytesTotal: Int64 = 0, current: String? = nil) {
        self.stage = stage; self.filesDone = filesDone; self.filesTotal = filesTotal
        self.bytesDone = bytesDone; self.bytesTotal = bytesTotal; self.current = current
    }
}

public struct BackupResult: Sendable {
    public let manifest: Manifest
    /// The snapshot's folder: its name if verified, else `.incomplete-...`.
    public let folder: URL
    /// Older snapshots thinned after it (W14), by name.
    public var removed: [String] = []
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
    /// W14: thin the card's older snapshots after a verified backup.
    public var thinning = false
    /// How thinned snapshots are removed (the Trash; the tests, elsewhere).
    public var remover: Repository.Remover = Repository.toTrash
    /// For the tests only (F2): skip the space check, to see a destination
    /// filling up mid-copy handled.
    var checksSpace = true
    /// The registered card being backed up (C3), recorded in the manifest.
    public var card: Card?

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
        if checksSpace, let free = repository.availableBytes, free < needed {
            throw BackupError.insufficientSpace(needed: needed, available: free)
        }

        let work = repository.workspace(for: id)
        let files = work.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        var entries = inventory.entries
        var warnings: [String] = inventory.notCleanlyShutDown.map { Inventory.uncleanWarning($0.path) }
        var progress = BackupProgress(stage: .copying, filesTotal: inventory.files.count,
                                      bytesTotal: inventory.totalBytes)
        var status = Manifest.Status.verified

        func finish(_ s: Manifest.Status) throws -> BackupResult {
            var m = manifest(id: id, name: name, status: s, started: started, source: source,
                             entries: entries, warnings: warnings)
            m.finished = Manifest.milliseconds(Date())
            try write(m, to: work)
            defer { _ = try? Catalog.rebuild(repository) }
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
            _ = try? Catalog.rebuild(repository)
            var removed: [String] = []
            if thinning {
                removed = (try? repository.thin(cardID: m.source.cardID, volumeUUID: m.source.volumeUUID,
                                                volumeName: m.source.volumeName, remover: remover)) ?? []
            }
            return BackupResult(manifest: m, folder: final, removed: removed)
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
                    } catch let change as FileCopy.SizeChanged {
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

    typealias SourceChanged = FileCopy.SizeChanged

    func copy(_ from: URL, to: URL, expected: Entry) throws -> String {
        try FileCopy.copy(from, to: to, size: expected.size, modified: expected.modified, created: expected.created)
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
                                      capacity: v?.volumeTotalCapacity.map(Int64.init),
                                      cardID: card?.id, cardName: card?.name),
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
