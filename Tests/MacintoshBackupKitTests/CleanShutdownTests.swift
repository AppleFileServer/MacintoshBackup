import Foundation
import Testing
@testable import MacintoshBackupKit

/// W13, on images made byte by byte: Apple's partition map, then the HFS
/// volume's header with its "unmounted cleanly" bit set or not.
@Suite struct CleanShutdownTests {
    let f: Fixtures
    init() throws { f = try Fixtures() }

    func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }

    func partitionEntry(type: String, start: Int, count: Int, entries: Int) -> Data {
        var d = Data(count: 512)
        d.replaceSubrange(0..<2, with: Array("PM".utf8))
        d.replaceSubrange(4..<8, with: be32(entries))
        d.replaceSubrange(8..<12, with: be32(start))
        d.replaceSubrange(12..<16, with: be32(count))
        d.replaceSubrange(48..<(48 + type.utf8.count), with: Array(type.utf8))
        return d
    }

    func volumeHeader(_ sig: String, clean: Bool) -> Data {
        var d = Data(count: 512)
        d.replaceSubrange(0..<2, with: Array(sig.utf8))
        if sig == "BD" { d.replaceSubrange(10..<12, with: be16(clean ? 0x0100 : 0)) }
        else { d.replaceSubrange(4..<8, with: be32(clean ? 0x0100 : 0)) }
        return d
    }

    /// A BlueSCSI-style image: descriptor, map (3 entries), HFS from block 96.
    func partitioned(clean: Bool, sig: String = "BD") throws -> URL {
        var d = Data(count: 512)
        d.replaceSubrange(0..<2, with: Array("ER".utf8))
        d.replaceSubrange(2..<4, with: be16(512))
        d += partitionEntry(type: "Apple_partition_map", start: 1, count: 63, entries: 3)
        d += partitionEntry(type: "Apple_Driver43", start: 64, count: 32, entries: 3)
        d += partitionEntry(type: "Apple_HFS", start: 96, count: 4000, entries: 3)
        d += Data(count: 96 * 512 + 1024 - d.count)
        d += volumeHeader(sig, clean: clean)
        d += Data(count: 4096)
        let u = f.url("HD\(clean ? 1 : 2)0_512 \(sig).hda")
        try d.write(to: u)
        return u
    }

    @Test func aPartitionedImage() throws {
        #expect(CleanShutdown.check(try partitioned(clean: true)) == .clean)
        #expect(CleanShutdown.check(try partitioned(clean: false)) == .notClean)
    }

    @Test func anImageWithNoPartitionMap() throws {
        for clean in [true, false] {
            let d = Data(count: 1024) + volumeHeader("BD", clean: clean) + Data(count: 1024)
            let u = f.url("FD\(clean ? 1 : 2).dsk")
            try d.write(to: u)
            #expect(CleanShutdown.check(u) == (clean ? .clean : .notClean))
        }
    }

    @Test func hfsPlusAndNotHFS() throws {
        #expect(CleanShutdown.check(try partitioned(clean: false, sig: "H+")) == .notClean)
        let other = f.url("HD3.hda")
        try Fixtures.data(5000).write(to: other)
        #expect(CleanShutdown.check(other) == .unknown)
        #expect(CleanShutdown.check(f.url("missing.hda")) == .unknown)
    }

    /// A disk hfsutils made and put away (as the Transfer Utility's are).
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/Retro68-build/toolchain/bin/hformat")))
    func aDiskHfsutilsMade() throws {
        let u = f.url("FD5.dsk")
        try Data(count: 800 * 1024).write(to: u)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/Retro68-build/toolchain/bin/hformat")
        p.arguments = ["-l", "Test", u.path]
        p.environment = ["HOME": f.folder.path]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        try #require(p.terminationStatus == 0)
        #expect(CleanShutdown.check(u) == .clean)
    }

    @Test func aBackupWarnsOfAnUncleanDisk() async throws {
        let card = try f.card()
        try FileManager.default.copyItem(at: try partitioned(clean: false), to: card.appendingPathComponent("HD40_512 Work.hda"))
        let r = try await SnapshotWriter(repository: f.repository()).backup(card)
        #expect(r.verified)
        #expect(r.manifest.entries.first { $0.path == "HD40_512 Work.hda" }?.cleanShutdown == false)
        #expect(r.manifest.warnings.contains { $0.hasPrefix("HD40_512 Work.hda wasn't shut down cleanly") })
        #expect(try Catalog.load(f.repository()).restorePoints.first?.unclean == true)
    }
}
