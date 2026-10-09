import CryptoKit
import Foundation
@testable import MacintoshBackupKit

/// A temporary folder per test, removed afterwards, and a made-up BlueSCSI
/// card in it: images, configuration, logs, macOS's own files, odd names.
final class Fixtures {
    let folder: URL
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mbu-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    deinit {
        // Unlock anything a test locked, then remove it all.
        if let w = FileManager.default.enumerator(atPath: folder.path) {
            for case let p as String in w {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent(p).path)
            }
        }
        try? FileManager.default.removeItem(at: folder)
    }
    func url(_ p: String) -> URL { folder.appendingPathComponent(p) }

    /// Bytes that aren't all zero: a pattern from a seed.
    static func data(_ count: Int, seed: UInt8 = 1) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) | 1 })
    }

    func write(_ path: String, _ data: Data, in root: URL) throws {
        let u = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
    }

    /// A card: `sparseMB` of mostly empty image (data only at its start
    /// and end), plus everything a real card might hold.
    func card(_ name: String = "card", sparseMB: Int = 8) throws -> URL {
        let root = url(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("HD60_512 Transfer.hda", Fixtures.data(300_000, seed: 2), in: root)
        try write("CD3.iso", Fixtures.data(70_000, seed: 3), in: root)
        try write("Images/HD1_512 Games.hda", Fixtures.data(50_000, seed: 4), in: root)
        try write("bluescsi.ini", Data("[SCSI]\nDir=/\n".utf8), in: root)
        try write("log.txt", Data("BlueSCSI v2 log\n".utf8), in: root)
        try write("lastlog.txt", Data("BlueSCSI v2 last log\n".utf8), in: root)
        try write("BlueSCSI_update.zip", Fixtures.data(1_000, seed: 5), in: root)
        try write("._HD60_512 Transfer.hda", Fixtures.data(4_096, seed: 6), in: root)
        try write(".fseventsd/fseventsd-uuid", Data("x".utf8), in: root)
        try write(".DS_Store", Fixtures.data(600, seed: 7), in: root)
        try write("empty.txt", Data(), in: root)
        try write("Café Mix ✓ (2).txt", Data("songs".utf8), in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty Folder"), withIntermediateDirectories: true)
        // The mostly empty image: data at the start and the end, zeros between.
        let image = root.appendingPathComponent("HD00_512 System.hda")
        FileManager.default.createFile(atPath: image.path, contents: nil)
        let h = try FileHandle(forWritingTo: image)
        try h.write(contentsOf: Fixtures.data(100_000, seed: 8))
        try h.truncate(atOffset: UInt64(sparseMB) * 1_048_576)
        try h.seekToEnd()
        try h.write(contentsOf: Fixtures.data(10_000, seed: 9))
        try h.close()
        return root
    }

    func repository(_ name: String = "repo") -> Repository { Repository(root: url(name)) }

    static func sha256(_ url: URL) throws -> String {
        let d = try Data(contentsOf: url)
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// The folders in Snapshots, hidden ones too.
    static func snapshotFolders(_ r: Repository) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: r.snapshots.path)) ?? []).sorted()
    }
}
