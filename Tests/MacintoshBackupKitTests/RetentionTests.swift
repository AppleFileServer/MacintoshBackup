import Foundation
import Testing
@testable import MacintoshBackupKit

/// W14: the owner's rule, on snapshots dated across more than a year.
@Suite struct RetentionTests {
    let now = Retention.calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 18))!

    func ago(days: Double, hours: Double = 0) -> Date { now.addingTimeInterval(-(days * 86_400 + hours * 3_600)) }
    func c(_ d: Date, pinned: Bool = false, clean: Bool = true) -> Retention.Candidate {
        Retention.Candidate(id: UUID(), started: d, pinned: pinned, clean: clean)
    }

    /// One backup a day, at 9 a.m., for 420 days.
    @Test func aDailyBackupForOverAYear() {
        let all = (0..<420).map { c(ago(days: Double($0), hours: 9)) }
        let removed = Set(Retention.toRemove(all, now: now))
        let kept = all.filter { !removed.contains($0.id) }.map(\.started)
        let cal = Retention.calendar
        // The last 7 days: each kept.
        #expect(kept.filter { $0 > ago(days: 7) }.count == 7)
        // A week to a month: one per week.
        let weeks = kept.filter { $0 <= ago(days: 7) && $0 > cal.date(byAdding: .month, value: -1, to: now)! }
        #expect(Set(weeks.map { cal.component(.weekOfYear, from: $0) }).count == weeks.count)
        #expect((3...4).contains(weeks.count))
        // A month to a year: one per month.
        let months = kept.filter { $0 <= cal.date(byAdding: .month, value: -1, to: now)! && $0 > cal.date(byAdding: .year, value: -1, to: now)! }
        #expect(Set(months.map { cal.component(.month, from: $0) }).count == months.count)
        #expect((11...12).contains(months.count))
        // Nothing older than a year.
        #expect(!kept.contains { $0 <= cal.date(byAdding: .year, value: -1, to: now)! })
    }

    @Test func theNewestOfEachDayIsKept() {
        let morning = c(ago(days: 2, hours: 10)), evening = c(ago(days: 2, hours: 2))
        let removed = Retention.toRemove([c(ago(days: 0)), morning, evening], now: now)
        #expect(removed == [morning.id])
    }

    @Test func alwaysAtLeastTwo() {
        let old = [c(ago(days: 500)), c(ago(days: 600)), c(ago(days: 700))]
        let removed = Retention.toRemove(old, now: now)
        #expect(removed == [old[2].id])
        #expect(Retention.toRemove(Array(old.prefix(2)), now: now).isEmpty)
        // Two the same day: both kept, to make two.
        #expect(Retention.toRemove([c(ago(days: 1, hours: 1)), c(ago(days: 1, hours: 3))], now: now).isEmpty)
    }

    @Test func aPinnedSnapshotIsKept() {
        let pinned = c(ago(days: 800), pinned: true)
        let removed = Retention.toRemove([c(ago(days: 0)), c(ago(days: 1)), pinned, c(ago(days: 900))], now: now)
        #expect(!removed.contains(pinned.id))
        #expect(removed.count == 1)
    }

    /// The newest is always kept; otherwise a clean one beats a newer unclean one.
    @Test func cleanIsPreferredButTheNewestStays() {
        let newestUnclean = c(ago(days: 0, hours: 1), clean: false)
        let earlierClean = c(ago(days: 0, hours: 5))
        let weekUnclean = c(ago(days: 10), clean: false), weekClean = c(ago(days: 11))
        let all = [newestUnclean, earlierClean, weekUnclean, weekClean]
        let removed = Set(Retention.toRemove(all, now: now))
        #expect(!removed.contains(newestUnclean.id) && !removed.contains(earlierClean.id))
        if Retention.calendar.component(.weekOfYear, from: weekUnclean.started) == Retention.calendar.component(.weekOfYear, from: weekClean.started) {
            #expect(removed == [weekUnclean.id])
        }
    }

    /// After real backups: thinned to the Trash stand-in, other cards and
    /// incomplete jobs untouched.
    @Test func thinningAfterABackup() async throws {
        let f = try Fixtures()
        let repo = f.repository(), card = try f.card()
        let bin = f.url("bin")
        let remover: Repository.Remover = { url in
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let to = bin.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: to)
            return to
        }
        var w = SnapshotWriter(repository: repo)
        w.thinning = true
        w.remover = remover
        let a = try await w.backup(card)
        let b = try await w.backup(card)
        #expect(a.removed.isEmpty && b.removed.isEmpty)       // two, so both kept
        let c3 = try await w.backup(card)
        #expect(c3.removed == [a.manifest.name])               // the same day: the oldest goes
        #expect(try Catalog.load(repo).restorePoints.map(\.snapshotID) == [b.manifest.snapshotID, c3.manifest.snapshotID])
        // Pinned: kept.
        try repo.setPinned(b.manifest.snapshotID, true)
        let d = try await w.backup(card)
        #expect(d.removed == [c3.manifest.name])
        #expect(try Verifier.verify(b.folder).passed)
        // An incomplete job is never thinned.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: card.appendingPathComponent("CD3.iso").path)
        let failed = try await w.backup(card)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: card.appendingPathComponent("CD3.iso").path)
        _ = try await w.backup(card)
        #expect(FileManager.default.fileExists(atPath: failed.folder.path))
    }
}
