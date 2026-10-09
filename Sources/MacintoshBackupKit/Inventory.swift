import Foundation

/// One thing found on the source (B6): its place relative to the root,
/// what it is, and, once copied, what happened to it.
public struct Entry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public enum Kind: String, Codable, Sendable { case file, folder, link, other }
    public enum Result: String, Codable, Sendable { case verified, skipped, failed, changed }

    public var path: String
    public var kind: Kind
    public var size: Int64
    public var sha256: String?
    public var modified: Date?
    public var created: Date?
    public var category: Category
    public var result: Result?
    public var note: String?
    /// A disk image's HFS volume: put away properly? (W13; nil if not
    /// found, or not a disk image.)
    public var cleanShutdown: Bool?
}

/// The source tree, read without writing to it (B7, B8): everything the
/// filesystem shows, hidden files included, in path order.
public struct Inventory: Sendable {
    public var entries: [Entry]
    /// Each file's identifier, to see it's still the same file afterwards.
    var fileIDs: [String: UInt64]

    public var files: [Entry] { entries.filter { $0.kind == .file } }
    /// Disk images whose volume wasn't put away properly (W13).
    public var notCleanlyShutDown: [Entry] { entries.filter { $0.cleanShutdown == false } }

    /// W13's warning, for the window and the manifest.
    public static func uncleanWarning(_ path: String) -> String {
        "\(path) wasn't shut down cleanly: the Plus may have lost power while using it. "
            + "This backup keeps it as it is; an earlier snapshot may be the better one to restore."
    }
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    static let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                         .contentModificationDateKey, .creationDateKey, .fileIdentifierKey]

    public static func scan(_ root: URL) throws -> Inventory {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [], errorHandler: { _, _ in true }) else {
            throw BackupError.sourceUnreadable(root.path)
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var entries: [Entry] = []
        var ids: [String: UInt64] = [:]
        for case let url as URL in walker {
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix) else { continue }
            let path = String(full.dropFirst(prefix.count))
            let v = try? url.resourceValues(forKeys: Set(keys))
            let kind: Entry.Kind = v?.isSymbolicLink == true ? .link
                : v?.isDirectory == true ? .folder : v?.isRegularFile == true ? .file : .other
            if kind == .link { walker.skipDescendants() }
            var e = Entry(path: path, kind: kind, size: kind == .file ? Int64(v?.fileSize ?? 0) : 0,
                          sha256: nil, modified: v?.contentModificationDate, created: v?.creationDate,
                          category: Category.of(path: path, isFolder: kind == .folder), result: nil, note: nil)
            if kind == .file, !FileManager.default.isReadableFile(atPath: url.path) {
                e.note = "It can't be read."
            } else if kind == .file, e.category == .diskImage {
                switch CleanShutdown.check(url) {
                case .clean: e.cleanShutdown = true
                case .notClean: e.cleanShutdown = false
                case .unknown: break
                }
            }
            if let id = v?.fileIdentifier { ids[path] = id }
            entries.append(e)
        }
        entries.sort { $0.path.compare($1.path, options: [.literal]) == .orderedAscending }
        return Inventory(entries: entries, fileIDs: ids)
    }
}
