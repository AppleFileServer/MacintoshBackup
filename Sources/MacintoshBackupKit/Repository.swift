import Foundation

/// The backup folder (B5; ARCHITECTURE.md): Catalog, Snapshots, Logs.
public struct Repository: Sendable {
    public let root: URL
    public var catalog: URL { root.appendingPathComponent("Catalog", isDirectory: true) }
    public var snapshots: URL { root.appendingPathComponent("Snapshots", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Mac Plus Backups", isDirectory: true)
    }

    public init(root: URL = Repository.defaultRoot) { self.root = root.standardizedFileURL }

    /// Makes the folders if they aren't there, and checks they can be written.
    public func prepare() throws {
        do {
            for f in [catalog, snapshots, logs] {
                try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            }
        } catch { throw BackupError.repositoryUnavailable(root.path) }
        guard FileManager.default.isWritableFile(atPath: snapshots.path) else {
            throw BackupError.repositoryUnavailable(root.path)
        }
    }

    public var availableBytes: Int64? {
        (try? snapshots.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// "2026-10-09_17-30-00_7f3a": the local start time, and the first four
    /// hex digits of the identifier.
    public static func snapshotName(started: Date, id: UUID) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: started) + "_" + id.uuidString.prefix(4).lowercased()
    }

    func workspace(for id: UUID) -> URL {
        snapshots.appendingPathComponent(".incomplete-\(id.uuidString)", isDirectory: true)
    }
}
