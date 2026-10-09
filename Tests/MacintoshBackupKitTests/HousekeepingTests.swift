import Foundation
import Testing
@testable import MacintoshBackupKit

/// Deleting only what's asked, confirmed, and the repository's own; to a
/// folder in the test's own temporary folder, never the owner's Trash.
@Suite struct HousekeepingTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    var remover: Repository.Remover {
        let bin = f.url("bin")
        return { url in
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let to = bin.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: to)
            return to
        }
    }

    @Test func aConfirmedSnapshotIsRemovedAndTheOtherKept() async throws {
        let repo = f.repository(), card = try f.card()
        let a = try await SnapshotWriter(repository: repo).backup(card)
        let b = try await SnapshotWriter(repository: repo).backup(card)
        #expect(try repo.otherRestorePoints(than: a.manifest.name, volumeUUID: a.manifest.source.volumeUUID).count == 1)
        try repo.delete(folder: a.manifest.name, id: a.manifest.snapshotID, confirmed: true, remover: remover)
        #expect(!FileManager.default.fileExists(atPath: a.folder.path))
        #expect(try Verifier.verify(b.folder).passed)
        #expect(try Catalog.load(repo).restorePoints.map(\.snapshotID) == [b.manifest.snapshotID])
        #expect(try repo.otherRestorePoints(than: b.manifest.name, volumeUUID: b.manifest.source.volumeUUID).isEmpty)
    }

    @Test func refusedUnlessConfirmedOwnAndMatching() async throws {
        let repo = f.repository(), card = try f.card()
        let a = try await SnapshotWriter(repository: repo).backup(card)
        #expect(throws: Repository.DeleteError.notConfirmed) {
            try repo.delete(folder: a.manifest.name, id: a.manifest.snapshotID, confirmed: false, remover: remover)
        }
        #expect(throws: Repository.DeleteError.wrongSnapshot) {
            try repo.delete(folder: a.manifest.name, id: UUID(), confirmed: true, remover: remover)
        }
        for bad in ["../\(a.manifest.name)", "..", "Catalog", "My stuff", a.manifest.name + "/Files"] {
            #expect(throws: Repository.DeleteError.self) {
                try repo.delete(folder: bad, id: a.manifest.snapshotID, confirmed: true, remover: remover)
            }
        }
        #expect(try Verifier.verify(a.folder).passed)
    }

    @Test func abandonedWorkCanBeCleared() async throws {
        let repo = f.repository(), card = try f.card()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: card.appendingPathComponent("CD3.iso").path)
        let failed = try await SnapshotWriter(repository: repo).backup(card)
        try repo.delete(folder: failed.folder.lastPathComponent, id: failed.manifest.snapshotID, confirmed: true, remover: remover)
        #expect(try Catalog.load(repo).snapshots.isEmpty)
    }
}
