import Foundation

/// Thinning a card's older snapshots (W14, the owner's rule): the newest
/// of each day for 7 days, of each week (from Monday) to a month, of each
/// month to a year, none older; always at least two; never a pinned one;
/// always the newest; where a period has one, the newest cleanly shut
/// down snapshot rather than a newer one that wasn't (W13). Pure: it says
/// what to remove, and `Repository.thin` does it.
public enum Retention {
    public struct Candidate: Sendable, Equatable {
        public var id: UUID
        public var started: Date
        public var pinned: Bool
        public var clean: Bool
        public init(id: UUID, started: Date, pinned: Bool = false, clean: Bool = true) {
            self.id = id; self.started = started; self.pinned = pinned; self.clean = clean
        }
    }

    public static let minimum = 2

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)      // weeks from Monday
        c.timeZone = .current
        return c
    }

    /// The period a snapshot falls in, or nil if it's over a year old.
    static func period(_ d: Date, now: Date, calendar c: Calendar) -> String? {
        let week = c.date(byAdding: .day, value: -7, to: now)!
        let month = c.date(byAdding: .month, value: -1, to: now)!
        let year = c.date(byAdding: .year, value: -1, to: now)!
        let p = c.dateComponents([.year, .month, .day, .yearForWeekOfYear, .weekOfYear], from: d)
        if d > week { return "day \(p.year!)-\(p.month!)-\(p.day!)" }
        if d > month { return "week \(p.yearForWeekOfYear!)-\(p.weekOfYear!)" }
        if d > year { return "month \(p.year!)-\(p.month!)" }
        return nil
    }

    /// The snapshots to remove, of one card's verified snapshots.
    public static func toRemove(_ all: [Candidate], now: Date) -> [UUID] {
        guard all.count > minimum else { return [] }
        let c = calendar
        let newestFirst = all.sorted { $0.started > $1.started }
        var keep = Set<UUID>()
        keep.insert(newestFirst[0].id)
        for s in all where s.pinned { keep.insert(s.id) }
        var periods: [String: [Candidate]] = [:]
        for s in newestFirst {
            if let p = period(s.started, now: now, calendar: c) { periods[p, default: []].append(s) }
        }
        for (_, list) in periods {
            keep.insert((list.first { $0.clean } ?? list[0]).id)
        }
        for s in newestFirst where keep.count < minimum { keep.insert(s.id) }
        return newestFirst.filter { !keep.contains($0.id) }.map(\.id)
    }
}

public extension Repository {
    /// Pins (Keep): in Catalog/pins.json, as a snapshot is never changed.
    var pinsURL: URL { catalog.appendingPathComponent("pins.json") }

    func pins() -> Set<UUID> {
        guard let d = try? Data(contentsOf: pinsURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: d) else { return [] }
        return Set(ids)
    }

    func setPinned(_ id: UUID, _ pinned: Bool) throws {
        var p = pins()
        if pinned { p.insert(id) } else { p.remove(id) }
        try prepare()
        try JSONEncoder().encode(p.sorted { $0.uuidString < $1.uuidString }).write(to: pinsURL, options: .atomic)
    }

    /// Thins one card's snapshots by the rule (W14); the names removed.
    @discardableResult
    func thin(card volumeUUID: String?, volumeName: String?, now: Date = Date(),
              remover: Remover = Repository.toTrash) throws -> [String] {
        let catalog = try Catalog.load(self)
        let pinned = pins()
        let mine = catalog.restorePoints.filter { s in
            volumeUUID != nil ? s.volumeUUID == volumeUUID : s.volumeName == volumeName
        }
        let candidates = mine.compactMap { s -> Retention.Candidate? in
            guard let id = s.snapshotID, let started = s.started else { return nil }
            return Retention.Candidate(id: id, started: started, pinned: pinned.contains(id), clean: !s.unclean)
        }
        var removed: [String] = []
        for id in Retention.toRemove(candidates, now: now) {
            guard let s = mine.first(where: { $0.snapshotID == id }) else { continue }
            try delete(folder: s.folder, id: id, confirmed: true, remover: remover)
            removed.append(s.name)
        }
        return removed
    }
}
