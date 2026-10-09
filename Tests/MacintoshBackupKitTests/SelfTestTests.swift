import Foundation
import Testing
@testable import MacintoshBackupKit

@Suite struct SelfTestTests {
    @Test func itPassesAndLeavesNothing() async {
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("mbu-selftest-") }
        let (passed, report) = await SelfTest.run()
        #expect(passed, "\(report)")
        #expect(report.last == "PASSED")
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("mbu-selftest-") }
        #expect(after == before)
    }

    @Test func itsImageReadsAsCleanOrNot() throws {
        let f = try Fixtures()
        for clean in [true, false] {
            let u = f.url("HD\(clean ? 1 : 2)0_512 T.hda")
            try SelfTest.image(cleanly: clean).write(to: u)
            #expect(CleanShutdown.check(u) == (clean ? .clean : .notClean))
        }
    }
}
