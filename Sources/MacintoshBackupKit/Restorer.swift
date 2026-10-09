import Foundation

/// Restoring from a snapshot to a folder (brief §11; B9): a file, a
/// folder, or the whole snapshot into a new folder. Each file is copied
/// under a hidden temporary name, checked against the manifest's SHA-256,
/// and only then given its name; nothing is replaced without the owner's
/// answer.
public struct Restorer: Sendable {
    public enum Conflict: String, Sendable { case skip, keepBoth, replace }

    public struct Options: Sendable {
        public var includeMacOSMetadata = true
        public var includeFirmware = true
        public init() {}
    }

    public struct Outcome: Sendable {
        public var destination: URL
        public var restored: [String] = []
        public var renamed: [String: String] = [:]
        public var skipped: [String] = []
        public var failed: [String: String] = [:]
        public var succeeded: Bool { failed.isEmpty }
    }

    public let snapshot: URL
    public let manifest: Manifest

    /// Only a complete, verified snapshot is a restore point (brief §5).
    public init(snapshot: URL) throws {
        let m = try Manifest.read(snapshot.appendingPathComponent(Manifest.fileName))
        guard m.status == .verified, !snapshot.lastPathComponent.hasPrefix(".incomplete-") else {
            throw BackupError.notARestorePoint(snapshot.lastPathComponent)
        }
        self.snapshot = snapshot
        self.manifest = m
    }

    /// The entries `paths` name (a path, or everything under a folder's
    /// path); all of them if `paths` is nil.
    public func entries(_ paths: [String]?, options: Options = Options()) -> [Entry] {
        manifest.entries.filter { e in
            if e.category == .macOSMetadata, !options.includeMacOSMetadata { return false }
            if e.category == .firmware, !options.includeFirmware { return false }
            guard e.result == .verified else { return false }
            guard let paths else { return true }
            return paths.contains { e.path == $0 || e.path.hasPrefix($0 + "/") }
        }
    }

    /// A new folder in `parent` for the whole snapshot: "Restored
    /// <snapshot name>", or with a number if that's taken.
    public func newFolder(in parent: URL) throws -> URL {
        var n = 1
        while true {
            let name = "Restored \(manifest.name)" + (n == 1 ? "" : " \(n)")
            let url = parent.appendingPathComponent(name, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            }
            n += 1
        }
    }

    public func restore(_ paths: [String]?, into destination: URL, options: Options = Options(),
                        conflict: @Sendable (String) -> Conflict,
                        onFile: @Sendable (String) -> Void = { _ in }) throws -> Outcome {
        var out = Outcome(destination: destination)
        let files = snapshot.appendingPathComponent("Files", isDirectory: true)
        var cleared = Set<String>()
        for e in entries(paths, options: options) {
            try Task.checkCancellation()
            let target = destination.appendingPathComponent(e.path)
            do {
                switch e.kind {
                case .folder:
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                case .file:
                    onFile(e.path)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    var final = target
                    if FileManager.default.fileExists(atPath: target.path) {
                        switch conflict(e.path) {
                        case .skip: out.skipped.append(e.path); continue
                        case .keepBoth: final = Restorer.free(target)
                        case .replace: break
                        }
                    }
                    let folder = target.deletingLastPathComponent()
                    if cleared.insert(folder.path).inserted { FileCopy.removeLeftovers(in: folder) }
                    let temp = folder.appendingPathComponent(".mbu-restore-\(UUID().uuidString)")
                    do {
                        let hash = try FileCopy.copy(files.appendingPathComponent(e.path), to: temp, size: e.size,
                                                     modified: e.modified, created: e.created)
                        guard hash == e.sha256 else {
                            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
                                "The backup's copy doesn't match its manifest: the backup may be damaged."])
                        }
                        if FileManager.default.fileExists(atPath: final.path) {
                            _ = try FileManager.default.replaceItemAt(final, withItemAt: temp)
                        } else {
                            try FileManager.default.moveItem(at: temp, to: final)
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: temp)
                        throw error
                    }
                    out.restored.append(e.path)
                    if final != target { out.renamed[e.path] = final.lastPathComponent }
                default:
                    break
                }
            } catch let c as CancellationError {
                throw c
            } catch {
                out.failed[e.path] = error.localizedDescription
            }
        }
        return out
    }

    /// "Name 2.ext", "Name 3.ext" ...: the first name not taken.
    static func free(_ url: URL) -> URL {
        let ext = url.pathExtension, base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = base + " \(n)" + (ext.isEmpty ? "" : "." + ext)
            let u = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }
}
