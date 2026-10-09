import Foundation

/// The index of a repository's snapshots (brief §9; B5), in
/// Catalog/catalog.json, for quick browsing. It is never the only record:
/// it is rebuilt from the snapshots' own manifests whenever it's missing
/// or damaged, and rebuilding reads the snapshots only.
public struct Catalog: Codable, Sendable, Equatable {
    public struct Summary: Codable, Sendable, Equatable, Identifiable {
        public var id: String { folder }
        public var snapshotID: UUID?
        public var name: String
        /// The folder's name in Snapshots: the snapshot's name, or
        /// `.incomplete-<UUID>`.
        public var folder: String
        /// The manifest's status; nil if there's no readable manifest.
        public var status: Manifest.Status?
        public var started: Date?
        public var finished: Date?
        public var files: Int
        public var bytes: Int64
        /// Space it takes on the disk (less than `bytes`, for sparse images).
        public var storedBytes: Int64
        public var volumeName: String?
        public var volumeUUID: String?
        public var cardID: UUID?
        public var cardName: String?
        public var warnings: Int
        public var problem: String?
        /// A disk image in it wasn't shut down cleanly (W13).
        public var unclean = false

        /// One card's snapshot (C3): by the card's register ID; a snapshot
        /// made before the card was registered (no ID) counts as the card's
        /// if its volume's UUID is the card's.
        public func isOfCard(_ id: UUID?, volumeUUID uuid: String?, volumeName name: String?) -> Bool {
            if let id, cardID == id { return true }
            guard cardID == nil else { return false }
            if let uuid { return volumeUUID == uuid }
            return id == nil && volumeName == name
        }

        /// A complete restore point: named, and verified when made.
        public var isRestorePoint: Bool { status == .verified && !folder.hasPrefix(".incomplete-") }
    }

    public static let schema = 1
    public var schemaVersion = Catalog.schema
    public var updated: Date
    public var snapshots: [Summary]

    public init(updated: Date, snapshots: [Summary]) {
        self.updated = updated
        self.snapshots = snapshots
    }

    public var restorePoints: [Summary] { snapshots.filter(\.isRestorePoint) }
    public var incomplete: [Summary] { snapshots.filter { !$0.isRestorePoint } }
    public var lastBackup: Summary? { restorePoints.max { ($0.started ?? .distantPast) < ($1.started ?? .distantPast) } }

    static func url(_ r: Repository) -> URL { r.catalog.appendingPathComponent("catalog.json") }

    /// Reads the catalogue, or rebuilds it if it's missing, damaged, or
    /// doesn't match the folders in Snapshots.
    public static func load(_ r: Repository) throws -> Catalog {
        if let data = try? Data(contentsOf: url(r)),
           let c = try? Manifest.decoder.decode(Catalog.self, from: data),
           Set(c.snapshots.map(\.folder)) == Set(folders(r)) {
            return c
        }
        return try rebuild(r)
    }

    /// Discovers every snapshot from its manifest and writes the index anew.
    @discardableResult
    public static func rebuild(_ r: Repository) throws -> Catalog {
        try r.prepare()
        var list: [Summary] = []
        for folder in folders(r) {
            let url = r.snapshots.appendingPathComponent(folder, isDirectory: true)
            let stored = allocated(url)
            do {
                let m = try Manifest.read(url.appendingPathComponent(Manifest.fileName))
                var s = Summary(snapshotID: m.snapshotID, name: m.name, folder: folder, status: m.status,
                                started: m.started, finished: m.finished, files: m.totals.files,
                                bytes: m.totals.bytes, storedBytes: stored, volumeName: m.source.volumeName,
                                volumeUUID: m.source.volumeUUID, cardID: m.source.cardID,
                                cardName: m.source.cardName, warnings: m.warnings.count, problem: nil,
                                unclean: m.entries.contains { $0.cleanShutdown == false })
                if !folder.hasPrefix(".incomplete-"), folder != m.name || m.status != .verified {
                    s.problem = "Its folder and its manifest don't agree."
                    s.status = nil
                }
                list.append(s)
            } catch let e as BackupError {
                list.append(Summary(snapshotID: nil, name: folder, folder: folder, status: nil, started: nil,
                                    finished: nil, files: 0, bytes: 0, storedBytes: stored, volumeName: nil,
                                    volumeUUID: nil, cardID: nil, cardName: nil, warnings: 0, problem: e.message))
            }
        }
        list.sort { ($0.started ?? .distantPast, $0.folder) < ($1.started ?? .distantPast, $1.folder) }
        let c = Catalog(updated: Manifest.milliseconds(Date()), snapshots: list)
        try Manifest.encoder.encode(c).write(to: url(r), options: .atomic)
        return c
    }

    /// The snapshot folders: named ones and `.incomplete-...` ones; nothing else.
    static func folders(_ r: Repository) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: r.snapshots.path)) ?? []).filter { name in
            var dir: ObjCBool = false
            let path = r.snapshots.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &dir), dir.boolValue else { return false }
            return name.hasPrefix(".incomplete-") || Repository.isSnapshotName(name)
        }.sorted()
    }

    static func allocated(_ folder: URL) -> Int64 {
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let u = walker?.nextObject() as? URL {
            total += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
