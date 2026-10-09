import Foundation
import Testing
@testable import MacintoshBackupKit

/// B13, Restore to a New Card: on exFAT and FAT32 disk images, never a
/// real card.
@Suite struct NewCardTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func snapshot() async throws -> (card: URL, snapshot: URL, manifest: Manifest) {
        let card = try f.card(sparseMB: 8)
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        try #require(r.verified)
        return (card, r.folder, r.manifest)
    }

    @Test func theChecks() async throws {
        let (_, _, m) = try await snapshot()
        #expect(NewCard.check(m, cardItems: [".fseventsd", ".Spotlight-V100", "._x", "System Volume Information"],
                              filesystem: "ExFAT", available: 10_000_000_000) == nil)
        #expect(NewCard.check(m, cardItems: ["photo.jpg", ".fseventsd"], filesystem: "ExFAT", available: nil) == .notEmpty(["photo.jpg"]))
        #expect(NewCard.check(m, cardItems: [], filesystem: "APFS", available: nil) == .notFAT("APFS"))
        #expect(NewCard.check(m, cardItems: [], filesystem: "MS-DOS (FAT32)", available: 10_000_000_000) == nil)
        var big = m
        let i = big.entries.firstIndex { $0.path == "HD60_512 Transfer.hda" }!
        big.entries[i].size = 5 * 1_073_741_824
        #expect(NewCard.check(big, cardItems: [], filesystem: "MS-DOS (FAT32)", available: nil) == .fileTooBigForFAT32("HD60_512 Transfer.hda"))
        #expect(NewCard.check(big, cardItems: [], filesystem: "ExFAT", available: nil) == nil)
        if case .notEnoughRoom = NewCard.check(m, cardItems: [], filesystem: "ExFAT", available: 1_000) {} else { Issue.record("room not checked") }
        // What goes: not macOS's files, not the firmware package (unless asked).
        let paths = NewCard.entries(m).map(\.path)
        #expect(!paths.contains { $0.hasPrefix(".") || $0.hasPrefix("._") } && !paths.contains("BlueSCSI_update.zip"))
        #expect(NewCard.entries(m, includeFirmware: true).map(\.path).contains("BlueSCSI_update.zip"))
    }

    func mount(_ fs: String, _ label: String) throws -> (URL, () -> Void) {
        let image = f.url("\(label).dmg"), mount = f.url(label)
        try run(["create", "-size", "64m", "-fs", fs, "-volname", label, "-layout", "MBRSPUD", "-quiet", image.path])
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run(["attach", "-nobrowse", "-noverify", "-mountpoint", mount.path, "-quiet", image.path])
        return (mount, { try? self.run(["detach", "-force", "-quiet", mount.path]) })
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")),
          arguments: [("ExFAT", "NEWEXFAT"), ("MS-DOS FAT32", "NEWFAT32")])
    func ontoAnEmptyCard(fs: String, label: String) async throws {
        let (card, snap, m) = try await snapshot()
        let (newCard, detach) = try mount(fs, label)
        defer { detach() }
        let o = try NewCard.restore(snap, onto: newCard)
        #expect(o.succeeded)
        #expect(o.checked == NewCard.entries(m).filter { $0.kind == .file }.count)
        for e in NewCard.entries(m) where e.kind == .file {
            #expect(try Fixtures.sha256(newCard.appendingPathComponent(e.path)) == Fixtures.sha256(card.appendingPathComponent(e.path)), "\(e.path)")
        }
        let all = try FileManager.default.subpathsOfDirectory(atPath: newCard.path)
        #expect(!all.contains { $0.contains(".mbu-restore-") })
        #expect(!all.contains("BlueSCSI_update.zip"))
        #expect(!all.contains { ($0 as NSString).lastPathComponent.hasPrefix("._") }, "\(all)")
        #expect(FileManager.default.fileExists(atPath: newCard.appendingPathComponent("Empty Folder").path))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")))
    func aCardWithSomethingOnItIsRefused() async throws {
        let (_, snap, _) = try await snapshot()
        let (newCard, detach) = try mount("ExFAT", "NOTEMPTY")
        defer { detach() }
        try Data("mine".utf8).write(to: newCard.appendingPathComponent("photo.jpg"))
        #expect(throws: NewCard.Problem.notEmpty(["photo.jpg"])) { try NewCard.restore(snap, onto: newCard) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: newCard.path).filter { !$0.hasPrefix(".") } == ["photo.jpg"])
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")))
    func aDamagedBackupLeavesTheCardAsItWas() async throws {
        let (_, snap, _) = try await snapshot()
        let file = snap.appendingPathComponent("Files/HD60_512 Transfer.hda")
        var d = try Data(contentsOf: file); d[5] ^= 1; try d.write(to: file)
        let (newCard, detach) = try mount("ExFAT", "DAMAGED")
        defer { detach() }
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: newCard.path))
        #expect(throws: (any Error).self) { try NewCard.restore(snap, onto: newCard) }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: newCard.path)) == before)
    }

    @Test func theNewCardTakesOverTheOldOnesEntry() {
        func v(_ uuid: String) -> VolumeInfo {
            VolumeInfo(url: URL(fileURLWithPath: "/Volumes/BLUESCSI"), name: "BLUESCSI", uuid: uuid, capacity: 15_000_000_000,
                       filesystem: "ExFAT", isRemovable: true, isEjectable: true)
        }
        var r = CardRegister()
        let old = r.register(v("OLD-UUID"), name: "Mac Plus BlueSCSI")
        let new = r.replace(old, with: v("NEW-UUID").with { $0.capacity = 32_000_000_000 })
        #expect(new.id == old.id && new.name == "Mac Plus BlueSCSI")
        #expect(r.match(v("NEW-UUID").with { $0.capacity = 32_000_000_000 }) == .known(r.cards[0]))
        #expect(r.cards[0].previousVolumeUUIDs == ["OLD-UUID"])
        // The old card turning up again: asked about, not taken for granted.
        if case .probably(let c) = r.match(v("OLD-UUID")) { #expect(c.id == old.id) } else { Issue.record("old card not recognised") }
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
