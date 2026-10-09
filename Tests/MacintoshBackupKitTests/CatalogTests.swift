import Foundation
import Testing
@testable import MacintoshBackupKit

@Suite struct CatalogTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func folderHashes(_ r: Repository) throws -> [String: String] {
        var out: [String: String] = [:]
        let w = FileManager.default.enumerator(at: r.snapshots, includingPropertiesForKeys: [.isRegularFileKey])
        while let u = w?.nextObject() as? URL {
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                out[u.path] = try Fixtures.sha256(u)
            }
        }
        return out
    }

    @Test func eachBackupIsCatalogued() async throws {
        let repo = f.repository(), card = try f.card()
        let a = try await SnapshotWriter(repository: repo).backup(card)
        let b = try await SnapshotWriter(repository: repo).backup(card)
        let c = try Catalog.load(repo)
        #expect(c.restorePoints.map(\.snapshotID) == [a.manifest.snapshotID, b.manifest.snapshotID])
        #expect(c.lastBackup?.snapshotID == b.manifest.snapshotID)
        #expect(c.restorePoints.allSatisfy { $0.files == a.manifest.totals.files && $0.storedBytes > 0 })
        #expect(FileManager.default.fileExists(atPath: repo.catalog.appendingPathComponent("catalog.json").path))
    }

    @Test func anIncompleteJobIsListedButIsNoRestorePoint() async throws {
        let repo = f.repository(), card = try f.card()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: card.appendingPathComponent("CD3.iso").path)
        _ = try await SnapshotWriter(repository: repo).backup(card)
        let c = try Catalog.load(repo)
        #expect(c.restorePoints.isEmpty)
        #expect(c.incomplete.count == 1 && c.incomplete[0].status == .failed)
        #expect(c.lastBackup == nil)
    }

    /// Lost or damaged: rebuilt from the manifests, and no snapshot changed.
    @Test func aLostOrDamagedCatalogueIsRebuilt() async throws {
        let repo = f.repository(), card = try f.card()
        let a = try await SnapshotWriter(repository: repo).backup(card)
        let before = try folderHashes(repo)
        let url = repo.catalog.appendingPathComponent("catalog.json")
        try FileManager.default.removeItem(at: url)
        #expect(try Catalog.load(repo).restorePoints.first?.snapshotID == a.manifest.snapshotID)
        try Data("{ not json".utf8).write(to: url)
        #expect(try Catalog.load(repo).restorePoints.count == 1)
        #expect(try folderHashes(repo) == before)
    }

    @Test func aCatalogueOutOfDateIsRebuilt() async throws {
        let repo = f.repository(), card = try f.card()
        _ = try await SnapshotWriter(repository: repo).backup(card)
        let url = repo.catalog.appendingPathComponent("catalog.json")
        let old = try Data(contentsOf: url)
        _ = try await SnapshotWriter(repository: repo).backup(card)
        try old.write(to: url)                       // as if the second hadn't been indexed
        #expect(try Catalog.load(repo).restorePoints.count == 2)
    }

    @Test func aSnapshotWithADamagedManifestIsFlagged() async throws {
        let repo = f.repository(), card = try f.card()
        let a = try await SnapshotWriter(repository: repo).backup(card)
        try Data("damaged".utf8).write(to: a.folder.appendingPathComponent(Manifest.fileName))
        let c = try Catalog.rebuild(repo)
        #expect(c.restorePoints.isEmpty)
        #expect(c.snapshots.first?.problem != nil)
    }

    @Test func otherFoldersAreNotSnapshots() async throws {
        let repo = f.repository()
        try repo.prepare()
        try FileManager.default.createDirectory(at: repo.snapshots.appendingPathComponent("My stuff"), withIntermediateDirectories: true)
        #expect(try Catalog.rebuild(repo).snapshots.isEmpty)
    }
}
