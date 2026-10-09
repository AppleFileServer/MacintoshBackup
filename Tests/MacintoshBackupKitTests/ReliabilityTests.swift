import Darwin
import Foundation
import Testing
@testable import MacintoshBackupKit

/// Stage 5 (F1-F6): failures, interruptions and size; after each, an
/// earlier snapshot still verifies byte for byte (F6).
@Suite struct ReliabilityTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    /// An earlier, good snapshot, and its manifest's SHA-256 (F6).
    func earlier(_ repo: Repository) async throws -> (URL, String) {
        let r = try await SnapshotWriter(repository: repo).backup(try f.card("first"))
        try #require(r.verified)
        return (r.folder, try Fixtures.sha256(r.folder.appendingPathComponent(Manifest.fileName)))
    }

    func intact(_ s: (URL, String)) throws {
        #expect(try Verifier.verify(s.0).passed)
        #expect(try Fixtures.sha256(s.0.appendingPathComponent(Manifest.fileName)) == s.1)
    }

    func peakMemory() -> Int {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Int(u.ru_maxrss)                    // bytes, on macOS
    }

    /// F1: a 3 GB image (mostly empty), backed up, verified and restored,
    /// with memory staying small.
    @Test func aThreeGigabyteImage() async throws {
        let repo = f.repository()
        let card = f.url("big")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let image = card.appendingPathComponent("HD00_512 Big.hda")
        FileManager.default.createFile(atPath: image.path, contents: nil)
        let h = try FileHandle(forWritingTo: image)
        try h.write(contentsOf: Fixtures.data(1_000_000))
        try h.truncate(atOffset: 3 * 1_073_741_824)
        try h.seekToEnd()
        try h.write(contentsOf: Fixtures.data(1_000_000, seed: 9))
        try h.close()
        let r = try await SnapshotWriter(repository: repo).backup(card)
        #expect(r.verified)
        #expect(try Verifier.verify(r.folder).passed)
        let dest = f.url("out")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let o = try Restorer(snapshot: r.folder).restore(nil, into: dest, conflict: { _ in .skip })
        #expect(o.succeeded)
        #expect(try Hashing.sha256(of: dest.appendingPathComponent("HD00_512 Big.hda")).hash
                == r.manifest.entries.first { $0.path == "HD00_512 Big.hda" }?.sha256)
        #expect(peakMemory() < 512 * 1_048_576, "peak \(peakMemory() / 1_048_576) MB")
    }

    /// F2: the destination fills up mid-copy.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")))
    func theDestinationFillsUp() async throws {
        let image = f.url("small.dmg"), mount = f.url("small")
        try run(["create", "-size", "40m", "-fs", "HFS+", "-volname", "mbu-full", "-quiet", image.path])
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run(["attach", "-nobrowse", "-noverify", "-mountpoint", mount.path, "-quiet", image.path])
        defer { try? run(["detach", "-force", "-quiet", mount.path]) }
        let repo = Repository(root: mount.appendingPathComponent("Backups"))
        let first = try await earlier(repo)
        let card = try f.card("second")
        try f.write("HD70_512 Large.hda", Fixtures.data(30_000_000, seed: 3), in: card)
        var w = SnapshotWriter(repository: repo)
        w.checksSpace = false
        let r = try? await w.backup(card)
        #expect(r?.verified != true)
        let c = try Catalog.load(repo)
        #expect(c.restorePoints.count == 1)
        #expect(Fixtures.snapshotFolders(repo).filter { Repository.isSnapshotName($0) }.count == 1)
        try intact(first)
    }

    /// F3: a backup interrupted with no record at all.
    @Test func anInterruptedBackup() async throws {
        let repo = f.repository()
        let first = try await earlier(repo)
        let work = repo.snapshots.appendingPathComponent(".incomplete-\(UUID().uuidString)/Files", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Fixtures.data(5000).write(to: work.appendingPathComponent("HD00_512 Half.hda"))
        let c = try Catalog.load(repo)
        #expect(c.restorePoints.count == 1)
        #expect(c.incomplete.count == 1 && c.incomplete[0].problem == Catalog.interrupted)
        let bin = f.url("bin")
        try repo.delete(folder: c.incomplete[0].folder, id: nil, confirmed: true) { url in
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
            return nil
        }
        #expect(try Catalog.load(repo).incomplete.isEmpty)
        try intact(first)
    }

    /// F4: an interrupted restore's temporary file is cleared next time, and
    /// only that.
    @Test func anInterruptedRestore() async throws {
        let repo = f.repository()
        let first = try await earlier(repo)
        let dest = f.url("out")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let stale = ".mbu-restore-\(UUID().uuidString)"
        try Data("half".utf8).write(to: dest.appendingPathComponent(stale))
        try Data("mine".utf8).write(to: dest.appendingPathComponent(".mbu-restore-notours"))
        let o = try Restorer(snapshot: first.0).restore(["CD3.iso"], into: dest, conflict: { _ in .skip })
        #expect(o.succeeded)
        let left = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        #expect(!left.contains(stale) && left.contains(".mbu-restore-notours") && left.contains("CD3.iso"))
        // On a new card, a stale one doesn't make the card "not empty".
        #expect(NewCard.isEmptyCardItem(stale) && !NewCard.isEmptyCardItem(".mbu-restore-notours"))
        try intact(first)
    }

    /// F5: the card vanishing mid-backup.
    @Test func theCardVanishesMidBackup() async throws {
        let repo = f.repository()
        let first = try await earlier(repo)
        let card = try f.card("pulled")
        var w = SnapshotWriter(repository: repo)
        w.afterCopy = { e in
            if e.path == "CD3.iso" { try? FileManager.default.removeItem(at: card) }
        }
        let r = try await w.backup(card)
        #expect(!r.verified)
        #expect(r.folder.lastPathComponent.hasPrefix(".incomplete-"))
        #expect(r.manifest.entries.contains { $0.result == .failed || $0.result == .changed })
        #expect(try Catalog.load(repo).restorePoints.count == 1)
        try intact(first)
    }

    func run(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}
