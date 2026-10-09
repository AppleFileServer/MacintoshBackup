import Foundation
import Testing
@testable import MacintoshBackupKit

@Suite struct RestoreTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func snapshot() async throws -> (URL, URL) {
        let card = try f.card(sparseMB: 16)
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        try #require(r.verified)
        return (card, r.folder)
    }

    @Test func aWholeSnapshotIntoANewFolder() async throws {
        let (card, snap) = try await snapshot()
        let restorer = try Restorer(snapshot: snap)
        let dest = try restorer.newFolder(in: f.url("restored"))
        #expect(dest.lastPathComponent == "Restored \(restorer.manifest.name)")
        let o = try restorer.restore(nil, into: dest, conflict: { _ in .skip })
        #expect(o.succeeded && o.skipped.isEmpty)
        for e in try Inventory.scan(card).files {
            #expect(try Fixtures.sha256(dest.appendingPathComponent(e.path)) == Fixtures.sha256(card.appendingPathComponent(e.path)), "\(e.path)")
        }
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("Empty Folder").path))
        // A second whole restore goes into a new folder of its own.
        #expect(try restorer.newFolder(in: f.url("restored")).lastPathComponent == "Restored \(restorer.manifest.name) 2")
        // Nothing temporary left behind.
        #expect(try !FileManager.default.subpathsOfDirectory(atPath: dest.path).contains { $0.contains(".mbu-restore-") })
    }

    @Test func oneFileAndOneFolder() async throws {
        let (card, snap) = try await snapshot()
        let dest = f.url("out")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let o = try Restorer(snapshot: snap).restore(["CD3.iso", "Images"], into: dest, conflict: { _ in .skip })
        #expect(Set(o.restored) == ["CD3.iso", "Images/HD1_512 Games.hda"])
        #expect(try Fixtures.sha256(dest.appendingPathComponent("Images/HD1_512 Games.hda"))
                == Fixtures.sha256(card.appendingPathComponent("Images/HD1_512 Games.hda")))
        #expect(!FileManager.default.fileExists(atPath: dest.appendingPathComponent("bluescsi.ini").path))
    }

    @Test func conflictsAreAskedNeverSilent() async throws {
        let (card, snap) = try await snapshot()
        let dest = f.url("out")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let mine = Data("my own file".utf8)
        for choice in [Restorer.Conflict.skip, .keepBoth, .replace] {
            try mine.write(to: dest.appendingPathComponent("CD3.iso"))
            try? FileManager.default.removeItem(at: dest.appendingPathComponent("CD3 2.iso"))
            final class Asked: @unchecked Sendable { var paths: [String] = [] }
            let asked = Asked()
            let o = try Restorer(snapshot: snap).restore(["CD3.iso"], into: dest, conflict: { p in asked.paths.append(p); return choice })
            #expect(asked.paths == ["CD3.iso"])
            let now = try Data(contentsOf: dest.appendingPathComponent("CD3.iso"))
            switch choice {
            case .skip:
                #expect(o.skipped == ["CD3.iso"] && now == mine)
            case .keepBoth:
                #expect(now == mine && o.renamed["CD3.iso"] == "CD3 2.iso")
                #expect(try Fixtures.sha256(dest.appendingPathComponent("CD3 2.iso")) == Fixtures.sha256(card.appendingPathComponent("CD3.iso")))
            case .replace:
                #expect(try Fixtures.sha256(dest.appendingPathComponent("CD3.iso")) == Fixtures.sha256(card.appendingPathComponent("CD3.iso")))
            }
        }
    }

    /// A damaged backup is caught while restoring, and nothing is put in place.
    @Test func aDamagedBackupFileIsNotRestored() async throws {
        let (_, snap) = try await snapshot()
        let file = snap.appendingPathComponent("Files/HD60_512 Transfer.hda")
        var d = try Data(contentsOf: file); d[10] ^= 1; try d.write(to: file)
        let dest = f.url("out")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let o = try Restorer(snapshot: snap).restore(["HD60_512 Transfer.hda"], into: dest, conflict: { _ in .skip })
        #expect(!o.succeeded && o.failed["HD60_512 Transfer.hda"] != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
    }

    @Test func anIncompleteSnapshotIsNotARestorePoint() async throws {
        let card = try f.card()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: card.appendingPathComponent("CD3.iso").path)
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        #expect(throws: BackupError.self) { try Restorer(snapshot: r.folder) }
    }

    @Test func leavingOutMacOSFilesAndFirmware() async throws {
        let (_, snap) = try await snapshot()
        var o = Restorer.Options()
        o.includeMacOSMetadata = false
        o.includeFirmware = false
        let paths = try Restorer(snapshot: snap).entries(nil, options: o).map(\.path)
        #expect(!paths.contains { $0.hasPrefix(".") || $0.hasPrefix("._") })
        #expect(!paths.contains("BlueSCSI_update.zip"))
        #expect(paths.contains("HD60_512 Transfer.hda") && paths.contains("bluescsi.ini"))
    }
}
