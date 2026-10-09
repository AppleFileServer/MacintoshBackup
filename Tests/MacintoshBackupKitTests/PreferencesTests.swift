import Foundation
import Testing
@testable import MacintoshBackupKit

@Suite struct PreferencesTests {
    @Test func remembered() {
        let d = UserDefaults(suiteName: "mbu-tests-\(UUID().uuidString)")!
        #expect(Preferences.load(from: d) == Preferences())
        #expect(Preferences().thinning)
        #expect(Preferences().repository.root.lastPathComponent == "Mac Plus Backups")
        var p = Preferences()
        p.repositoryPath = "/tmp/elsewhere"
        p.thinning = false
        p.save(to: d)
        #expect(Preferences.load(from: d) == p)
        #expect(Preferences.load(from: d).repository.root.path == "/tmp/elsewhere")
    }
}
