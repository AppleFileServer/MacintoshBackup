import Foundation
import Testing
@testable import MacintoshBackupKit

/// Checking a snapshot later (brief §7). The damage is done to copies in
/// a temporary folder, never to a real backup.
@Suite struct VerifierTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func snapshot() async throws -> URL {
        let r = try await SnapshotWriter(repository: f.repository()).backup(try f.card())
        try #require(r.verified)
        return r.folder
    }

    @Test func aGoodSnapshotPasses() async throws {
        let s = try await snapshot()
        let before = try Fixtures.sha256(s.appendingPathComponent(Manifest.fileName))
        let v = try Verifier.verify(s)
        #expect(v.passed)
        #expect(v.filesChecked == v.manifest.totals.files)
        #expect(try Fixtures.sha256(s.appendingPathComponent(Manifest.fileName)) == before)
    }

    @Test func aChangedByteIsFound() async throws {
        let s = try await snapshot()
        let file = s.appendingPathComponent("Files/HD60_512 Transfer.hda")
        var d = try Data(contentsOf: file)
        d[1000] ^= 0xFF
        try d.write(to: file)
        let v = try Verifier.verify(s)
        #expect(!v.passed)
        #expect(v.problems == [.init(path: "HD60_512 Transfer.hda", kind: .wrongChecksum)])
    }

    @Test func missingAndUnexpectedFilesAreFound() async throws {
        let s = try await snapshot()
        try FileManager.default.removeItem(at: s.appendingPathComponent("Files/CD3.iso"))
        try Data("?".utf8).write(to: s.appendingPathComponent("Files/stray.txt"))
        let v = try Verifier.verify(s)
        #expect(v.problems.contains(.init(path: "CD3.iso", kind: .missing)))
        #expect(v.problems.contains(.init(path: "stray.txt", kind: .unexpected)))
    }

    @Test func aDamagedManifestIsRefused() async throws {
        let s = try await snapshot()
        let url = s.appendingPathComponent(Manifest.fileName)
        var d = try Data(contentsOf: url)
        d.removeLast(d.count / 2)
        try d.write(to: url)
        #expect(throws: BackupError.self) { try Verifier.verify(s) }
    }

    @Test func totalsThatDisagreeAreRefused() async throws {
        let s = try await snapshot()
        let url = s.appendingPathComponent(Manifest.fileName)
        var m = try Manifest.read(url)
        m.totals.files += 1
        try m.encoded().write(to: url)
        #expect(throws: BackupError.self) { try Manifest.read(url) }
    }

    @Test func aLaterVersionsFieldsDoNotBreakReading() async throws {
        let s = try await snapshot()
        let url = s.appendingPathComponent(Manifest.fileName)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["schemaVersion"] = 2
        json["somethingNew"] = ["a": 1]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(try Manifest.read(url).schemaVersion == 2)
    }

    @Test func snapshotNames() {
        let d = Date(timeIntervalSince1970: 1_791_000_000)
        let a = Repository.snapshotName(started: d, id: UUID()), b = Repository.snapshotName(started: d, id: UUID())
        #expect(a.count == "2026-10-09_17-30-00_7f3a".count)
        #expect(a.dropLast(4) == b.dropLast(4))
    }
}
