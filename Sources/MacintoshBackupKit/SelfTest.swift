import Foundation

/// The packaged app's self-test (Stage 6), as the other utilities' have:
/// run as `Macintosh Backup Utility.app/Contents/MacOS/MacintoshBackup
/// --self-test`, it opens no window and touches neither a card nor the
/// owner's backups: in a temporary folder it makes a small card (a disk
/// image put away cleanly, `bluescsi.ini`, a log), recognises it, backs
/// it up, verifies the snapshot, restores it to a folder, compares, then
/// removes everything it made, and reports.
public enum SelfTest {
    public static func run() async -> (passed: Bool, report: [String]) {
        var report = ["\(AppVersion.name) \(AppVersion.string): self-test"]
        func fail(_ s: String) -> (Bool, [String]) { report.append("FAIL: " + s); return (false, report) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mbu-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            let card = work.appendingPathComponent("Card", isDirectory: true)
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try image(cleanly: true).write(to: card.appendingPathComponent("HD00_512 Self Test.hda"))
            try Data("[SCSI]\n".utf8).write(to: card.appendingPathComponent("bluescsi.ini"))
            try Data("BlueSCSI self-test log\n".utf8).write(to: card.appendingPathComponent("log.txt"))
            guard Evidence.of(card) == .strong else { return fail("the test card wasn't recognised") }
            report.append("ok    recognised as a BlueSCSI card")

            let repo = Repository(root: work.appendingPathComponent("Backups", isDirectory: true))
            let r = try await SnapshotWriter(repository: repo).backup(card)
            guard r.verified else { return fail("the backup wasn't verified: \(r.manifest.status.rawValue)") }
            guard r.manifest.entries.first(where: { $0.category == .diskImage })?.cleanShutdown == true else {
                return fail("the disk image's clean shutdown wasn't read")
            }
            report.append("ok    backed up and verified: \(r.manifest.totals.files) files, \(r.manifest.totals.bytes) bytes")

            let v = try Verifier.verify(r.folder)
            guard v.passed else { return fail("verifying found \(v.problems.count) problem(s)") }
            report.append("ok    verified again from the snapshot alone")

            let restorer = try Restorer(snapshot: r.folder)
            let dest = try restorer.newFolder(in: work)
            let o = try restorer.restore(nil, into: dest, conflict: { _ in .skip })
            guard o.succeeded else { return fail("restoring failed: \(o.failed)") }
            for e in restorer.manifest.entries where e.kind == .file {
                let got = try Hashing.sha256(of: dest.appendingPathComponent(e.path))
                guard got.hash == e.sha256 else { return fail("\(e.path) didn't restore as it was") }
            }
            report.append("ok    restored to a folder: \(o.restored.count) files, each as it was")
            guard try Catalog.load(repo).restorePoints.count == 1 else { return fail("the catalogue is wrong") }
            report.append("ok    catalogued")
        } catch let e as BackupError {
            return fail(e.message)
        } catch {
            return fail("\(error)")
        }
        report.append("PASSED")
        return (true, report)
    }

    /// A small HFS disk image, as a BlueSCSI holds one: Apple's partition
    /// map, then a volume header with its "unmounted cleanly" mark.
    static func image(cleanly: Bool) -> Data {
        func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }
        func entry(_ type: String, _ start: Int, _ count: Int) -> Data {
            var d = Data(count: 512)
            d.replaceSubrange(0..<2, with: Array("PM".utf8))
            d.replaceSubrange(4..<8, with: be32(2))
            d.replaceSubrange(8..<12, with: be32(start))
            d.replaceSubrange(12..<16, with: be32(count))
            d.replaceSubrange(48..<(48 + type.utf8.count), with: Array(type.utf8))
            return d
        }
        var d = Data(count: 512)
        d.replaceSubrange(0..<2, with: Array("ER".utf8))
        d.replaceSubrange(2..<4, with: be16(512))
        d += entry("Apple_partition_map", 1, 63) + entry("Apple_HFS", 64, 2048)
        d += Data(count: 64 * 512 + 1024 - d.count)
        var header = Data(count: 512)
        header.replaceSubrange(0..<2, with: Array("BD".utf8))
        header.replaceSubrange(10..<12, with: be16(cleanly ? 0x0100 : 0))
        d += header
        d += Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        d += Data(count: 600_000)
        return d
    }
}
