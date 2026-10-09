import Foundation
import Testing
@testable import MacintoshBackupKit

@Suite struct BackupTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    @Test func aVerifiedSnapshotOfEverything() async throws {
        let card = try f.card()
        let repo = f.repository()
        let r = try await SnapshotWriter(repository: repo).backup(card)
        #expect(r.verified)
        #expect(r.folder.lastPathComponent == r.manifest.name)
        #expect(r.manifest.name.wholeMatch(of: /\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d_[0-9a-f]{4}/) != nil)
        // Every file there, byte for byte, hidden ones too.
        let source = try Inventory.scan(card)
        #expect(r.manifest.totals.files == source.files.count)
        for e in source.files {
            let copy = r.folder.appendingPathComponent("Files").appendingPathComponent(e.path)
            let want = try Fixtures.sha256(card.appendingPathComponent(e.path))
            #expect(try Fixtures.sha256(copy) == want, "\(e.path)")
            #expect(r.manifest.entries.first { $0.path == e.path }?.sha256 == want)
        }
        #expect(FileManager.default.fileExists(atPath: r.folder.appendingPathComponent("Files/Empty Folder").path))
        #expect(FileManager.default.fileExists(atPath: r.folder.appendingPathComponent("Files/.fseventsd/fseventsd-uuid").path))
        // The manifest is in the snapshot, and reads back.
        let m = try Manifest.read(r.folder.appendingPathComponent(Manifest.fileName))
        #expect(m == r.manifest)
        // Only the verified snapshot: no work left behind.
        #expect(Fixtures.snapshotFolders(repo) == [r.manifest.name])
    }

    /// Stage 1's deliverable: the snapshot stands without its source.
    @Test func aSnapshotVerifiesWithTheSourceGone() async throws {
        let card = try f.card()
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        try FileManager.default.removeItem(at: card)
        #expect(try Verifier.verify(r.folder).passed)
    }

    @Test func datesReadBackExactly() throws {
        for t in [1_791_563_730.6225, 1_791_563_730.0, -86_400.25, 0.0005] {
            let d = Manifest.milliseconds(Date(timeIntervalSince1970: t))
            #expect(Manifest.date(Manifest.dateText(d)) == d, "\(t): \(Manifest.dateText(d))")
        }
    }

    @Test func theCategories() {
        #expect(Category.of(path: "HD60_512 Transfer.hda") == .diskImage)
        #expect(Category.of(path: "Images/HD1_512 Games.hda") == .diskImage)
        #expect(Category.of(path: "CD3.iso") == .diskImage)
        #expect(Category.of(path: "hd.hda") == .diskImage)
        #expect(Category.of(path: "readme.txt") == .other)
        #expect(Category.of(path: "bluescsi.ini") == .configuration)
        #expect(Category.of(path: "log.txt") == .log)
        #expect(Category.of(path: "lastlog.txt") == .log)
        #expect(Category.of(path: "BlueSCSI_update.zip") == .firmware)
        #expect(Category.of(path: "._HD60_512 Transfer.hda") == .macOSMetadata)
        #expect(Category.of(path: ".fseventsd/fseventsd-uuid") == .macOSMetadata)
        #expect(Category.of(path: ".Spotlight-V100", isFolder: true) == .macOSMetadata)
        #expect(Category.of(path: String(repeating: "h", count: 1) + "d0" + String(repeating: "x", count: 70)) == .other)
    }

    /// B14: a mostly empty image takes little room in the backup, and is
    /// still every byte.
    @Test func emptySpaceIsLeftAsHoles() async throws {
        let card = try f.card(sparseMB: 64)
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        #expect(r.verified)
        let copy = r.folder.appendingPathComponent("Files/HD00_512 System.hda")
        let v = try copy.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        #expect(Int64(v.fileSize ?? 0) == 64 * 1_048_576 + 10_000)
        #expect((v.totalFileAllocatedSize ?? .max) < 4 * 1_048_576, "allocated \(v.totalFileAllocatedSize ?? -1)")
        #expect(try Fixtures.sha256(copy) == Fixtures.sha256(card.appendingPathComponent("HD00_512 System.hda")))
    }

    @Test func eachBackupIsANewSnapshotAndTheFirstIsUntouched() async throws {
        let card = try f.card()
        let repo = f.repository()
        let first = try await SnapshotWriter(repository: repo).backup(card)
        let before = try Fixtures.sha256(first.folder.appendingPathComponent(Manifest.fileName))
        let second = try await SnapshotWriter(repository: repo).backup(card)
        #expect(first.verified && second.verified)
        #expect(first.manifest.snapshotID != second.manifest.snapshotID)
        #expect(first.folder != second.folder)
        #expect(try Fixtures.sha256(first.folder.appendingPathComponent(Manifest.fileName)) == before)
        #expect(try Verifier.verify(first.folder).passed)
        #expect(Fixtures.snapshotFolders(repo).count == 2)
    }

    /// A file changed on the card during the backup: inconsistent, never
    /// verified, never given a name.
    @Test func aSourceChangedMidBackup() async throws {
        let card = try f.card()
        let repo = f.repository()
        var w = SnapshotWriter(repository: repo)
        let target = card.appendingPathComponent("CD3.iso")
        w.afterCopy = { e in
            if e.path == "CD3.iso" {
                let h = try? FileHandle(forWritingTo: target)
                try? h?.seekToEnd()
                try? h?.write(contentsOf: Data("more".utf8))
                try? h?.close()
            }
        }
        let r = try await w.backup(card)
        #expect(r.manifest.status == .inconsistent)
        #expect(r.manifest.entries.first { $0.path == "CD3.iso" }?.result == .changed)
        #expect(r.folder.lastPathComponent.hasPrefix(".incomplete-"))
        #expect(Fixtures.snapshotFolders(repo).allSatisfy { $0.hasPrefix(".incomplete-") })
        #expect(try !Verifier.verify(r.folder).passed)
    }

    @Test func anUnreadableFileFailsTheSnapshot() async throws {
        let card = try f.card()
        let locked = card.appendingPathComponent("CD3.iso")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        #expect(r.manifest.status == .failed)
        #expect(r.manifest.entries.first { $0.path == "CD3.iso" }?.result == .failed)
        #expect(r.folder.lastPathComponent.hasPrefix(".incomplete-"))
    }

    @Test func aSymbolicLinkIsNotedAndSkipped() async throws {
        let card = try f.card()
        try FileManager.default.createSymbolicLink(at: card.appendingPathComponent("link.hda"),
                                                   withDestinationURL: card.appendingPathComponent("CD3.iso"))
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        #expect(r.verified)
        #expect(r.manifest.entries.first { $0.path == "link.hda" }?.result == .skipped)
        #expect(r.manifest.warnings.contains { $0.hasPrefix("link.hda") })
    }

    @Test func cancelledMidway() async throws {
        let card = try f.card(sparseMB: 256)
        let repo = f.repository()
        let task = Task { try await SnapshotWriter(repository: repo).backup(card) { p in
            if p.stage == .copying, p.filesDone >= 1 { withUnsafeCurrentTask { $0?.cancel() } }
        } }
        let r = try await task.value
        #expect(r.manifest.status == .cancelled)
        #expect(Fixtures.snapshotFolders(repo).allSatisfy { $0.hasPrefix(".incomplete-") })
    }

    /// Too little room: refused before anything is copied.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")))
    func notEnoughRoom() async throws {
        let card = try f.card(sparseMB: 1)
        try f.write("big.hda", Fixtures.data(12_000_000), in: card)
        let image = f.url("small.dmg"), mount = f.url("small")
        try run("/usr/bin/hdiutil", ["create", "-size", "8m", "-fs", "HFS+", "-volname", "mbu-small", "-quiet", image.path])
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", "-mountpoint", mount.path, "-quiet", image.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-force", "-quiet", mount.path]) }
        let repo = Repository(root: mount.appendingPathComponent("Backups"))
        await #expect(throws: BackupError.self) { try await SnapshotWriter(repository: repo).backup(card) }
        #expect(Fixtures.snapshotFolders(repo).isEmpty)
    }

    func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}
