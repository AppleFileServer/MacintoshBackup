import Foundation
import Testing
@testable import MacintoshBackupKit

/// Stage 4 (C1-C4, C7): recognising a card, the register, the watcher;
/// on folders and disk images only, never a real card.
@Suite struct CardTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func folder(_ name: String, _ files: [String: String]) throws -> URL {
        let u = f.url(name)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        for (n, text) in files { try f.write(n, Data(text.utf8), in: u) }
        return u
    }

    @Test func theEvidence() throws {
        #expect(Evidence.of(try folder("a", ["bluescsi.ini": "[SCSI]"])) == .strong)
        #expect(Evidence.of(try folder("b", ["log.txt": "Platform: BlueSCSI v2\n"])) == .strong)
        #expect(Evidence.of(try folder("c", ["lastlog.txt": "BLUESCSI V2025.10\n"])) == .strong)
        #expect(Evidence.of(try folder("d", ["HD60_512 Transfer.hda": "x"])) == .likely)
        #expect(Evidence.of(try folder("e", ["DCIM/IMG_0001.JPG": "x", "MISC/readme.txt": "x"])) == .none)
        #expect(Evidence.of(try folder("g", ["log.txt": "camera log\n", "._HD1.hda": "x"])) == .none)
        #expect(Evidence.of(f.url("missing")) == .none)
        #expect(Evidence.strong > .likely && Evidence.likely > .none)
    }

    func volume(_ uuid: String?, name: String = "BLUESCSI", capacity: Int64 = 32_000_000_000,
                inside: Bool = false, ejectable: Bool = true) -> VolumeInfo {
        VolumeInfo(url: URL(fileURLWithPath: "/Volumes/" + name), name: name, uuid: uuid, capacity: capacity,
                   filesystem: "ExFAT", isRemovable: true, isEjectable: ejectable, isInternal: inside,
                   deviceModel: "SD Card Reader")
    }

    @Test func theRegister() throws {
        var r = CardRegister()
        let v = volume("AAAA-1111")
        #expect(r.match(v) == .new)
        let card = r.register(v, name: "Mac Plus BlueSCSI")
        #expect(r.match(v) == .known(card))
        // Reformatted: a new UUID, the same name, size and format: ask.
        let reformatted = volume("BBBB-2222")
        guard case .probably(let c) = r.match(reformatted) else { Issue.record("not a probable match"); return }
        #expect(c.id == card.id)
        r.confirm(c, is: reformatted)
        #expect(r.match(reformatted) == .known(r.cards[0]))
        // A different card altogether.
        #expect(r.match(volume("CCCC-3333", name: "OTHER")) == .new)
        #expect(r.match(volume("DDDD-4444", capacity: 64_000_000_000)) == .new)
        r.rename(card, to: "Plus Card")
        #expect(r.cards[0].name == "Plus Card")
        // Saved and read back.
        let repo = f.repository()
        try r.save(repo)
        #expect(CardRegister.load(repo) == r)
        #expect(CardRegister.load(f.repository("empty")) == CardRegister())
    }

    @Test func theWatcher() {
        var w = CardWatcher()
        var r = CardRegister()
        // The Mac's own disks and disks without any sign of BlueSCSI: nothing.
        #expect(w.mounted(volume("I", inside: true), evidence: .strong, register: r) == .ignore)
        #expect(w.mounted(volume("N", ejectable: false).with { $0.isRemovable = false }, evidence: .strong, register: r) == .ignore)
        #expect(w.mounted(volume("CAM", name: "CAMERA"), evidence: .none, register: r) == .ignore)
        // A BlueSCSI card: one offer, however many notifications.
        let v = volume("AAAA-1111")
        #expect(w.mounted(v, evidence: .strong, register: r) == .offer(v, .strong, .new))
        #expect(w.mounted(v, evidence: .strong, register: r) == .ignore)
        // Gone, and back: offered again, now as the registered card.
        #expect(w.unmounted(v.url) == .gone(v.url))
        #expect(w.unmounted(v.url) == .ignore)
        let card = r.register(v, name: "Mac Plus BlueSCSI")
        #expect(w.mounted(v, evidence: .none, register: r) == .offer(v, .none, .known(card)))
    }

    /// Thinning keeps each registered card's snapshots apart.
    @Test func thinningIsPerCard() async throws {
        let repo = f.repository(), card = try f.card()
        let bin = f.url("bin")
        var w = SnapshotWriter(repository: repo)
        w.thinning = true
        w.remover = { url in
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
            return nil
        }
        var reg = CardRegister()
        let a = reg.register(volume("A"), name: "Card A"), b = reg.register(volume("B"), name: "Card B")
        w.card = a
        for _ in 0..<2 { _ = try await w.backup(card) }
        w.card = b
        for _ in 0..<3 { _ = try await w.backup(card) }
        let points = try Catalog.load(repo).restorePoints
        #expect(points.filter { $0.cardID == a.id }.count == 2)
        #expect(points.filter { $0.cardID == b.id }.count == 2)
        #expect(points.allSatisfy { $0.cardName == ($0.cardID == a.id ? "Card A" : "Card B") })
    }

    /// A snapshot made before the card was registered counts as its own.
    @Test func snapshotsFromBeforeRegisteringBelongToTheCard() {
        func summary(_ card: UUID?, _ uuid: String?) -> Catalog.Summary {
            Catalog.Summary(snapshotID: UUID(), name: "s", folder: "s", status: .verified, started: Date(), finished: Date(),
                            files: 1, bytes: 1, storedBytes: 1, volumeName: "BLUESCSI", volumeUUID: uuid,
                            cardID: card, cardName: nil, warnings: 0, problem: nil)
        }
        let id = UUID(), other = UUID()
        #expect(summary(id, "A").isOfCard(id, volumeUUID: "A", volumeName: nil))
        #expect(summary(nil, "A").isOfCard(id, volumeUUID: "A", volumeName: nil))
        #expect(!summary(nil, "B").isOfCard(id, volumeUUID: "A", volumeName: nil))
        #expect(!summary(other, "A").isOfCard(id, volumeUUID: "A", volumeName: nil))
    }

    /// Real mounts (C7): exFAT and FAT32 disk images, as a card would be.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")),
          arguments: [("ExFAT", "MBUEXFAT"), ("MS-DOS FAT32", "MBUFAT32")])
    func aMountedFATDisk(fs: String, label: String) throws {
        let image = f.url("\(label).dmg"), mount = f.url(label)
        try run("/usr/bin/hdiutil", ["create", "-size", "40m", "-fs", fs, "-volname", label, "-layout", "MBRSPUD", "-quiet", image.path])
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", "-mountpoint", mount.path, "-quiet", image.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-force", "-quiet", mount.path]) }
        let v = VolumeInfo.of(mount)
        #expect(v.name == label)
        #expect(v.uuid != nil)
        #expect(v.isCandidate, "removable \(v.isRemovable) ejectable \(v.isEjectable) internal \(v.isInternal)")
        #expect(v.filesystem != nil)
        #expect(Evidence.of(mount) == .none)
        try Data("[SCSI]\n".utf8).write(to: mount.appendingPathComponent("bluescsi.ini"))
        try Fixtures.data(100_000).write(to: mount.appendingPathComponent("HD60_512 Transfer.hda"))
        #expect(Evidence.of(mount) == .strong)
    }

    func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}

extension VolumeInfo {
    func with(_ change: (inout VolumeInfo) -> Void) -> VolumeInfo { var v = self; change(&v); return v }
}
