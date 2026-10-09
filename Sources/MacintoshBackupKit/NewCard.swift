import Foundation

/// Restoring a snapshot onto a new, empty card (B13): only an empty card
/// (nothing on it but macOS's own files), never formatted by the app;
/// exFAT preferred, FAT32 refused if a file is 4 GB or more; room enough;
/// everything but macOS's files and BlueSCSI firmware packages (which
/// would make it reflash itself; includable deliberately); one file at a
/// time, under a hidden temporary name, renamed once its read-back
/// matches; only the app's own files removed on a failure; no extended
/// attributes written, so macOS adds no `._` files; the whole card
/// checked afterwards.
public enum NewCard {
    public enum Problem: Error, Equatable, Sendable {
        case notEmpty([String])
        case notFAT(String?)
        case fileTooBigForFAT32(String)
        case notEnoughRoom(needed: Int64, available: Int64)

        public var message: String {
            switch self {
            case .notEmpty(let names):
                "The card isn't empty (\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? "…" : "")). Restore only onto a newly formatted card, so nothing on it can be replaced."
            case .notFAT(let fs):
                "The card is formatted as \(fs ?? "something unknown"); BlueSCSI needs exFAT (or FAT32). Format it as exFAT first."
            case .fileTooBigForFAT32(let name):
                "\(name) is 4 GB or more, too big for FAT32. Format the card as exFAT instead."
            case .notEnoughRoom(let n, let a):
                "The card is too small: it needs \(n / 1_000_000) MB, and has \(a / 1_000_000) MB free."
            }
        }
    }

    public static let fat32Limit: Int64 = 4 * 1_073_741_824 - 1

    /// Names a freshly formatted card may hold: macOS's, and Windows's.
    static func isEmptyCardItem(_ name: String) -> Bool {
        Category.of(path: name) == .macOSMetadata || name == "System Volume Information" || name == "$RECYCLE.BIN"
    }

    /// What would go onto the card.
    public static func entries(_ m: Manifest, includeFirmware: Bool = false) -> [Entry] {
        m.entries.filter { e in
            guard e.result == .verified, e.category != .macOSMetadata else { return false }
            return includeFirmware || e.category != .firmware
        }
    }

    /// Whether the card can take the snapshot (pure: tested without a card).
    public static func check(_ m: Manifest, cardItems: [String], filesystem: String?, available: Int64?,
                             includeFirmware: Bool = false) -> Problem? {
        let extra = cardItems.filter { !isEmptyCardItem($0) }
        if !extra.isEmpty { return .notEmpty(extra.sorted()) }
        let fs = (filesystem ?? "").lowercased()
        let exfat = fs.contains("exfat"), fat = fs.contains("fat") || fs.contains("ms-dos")
        guard exfat || fat else { return .notFAT(filesystem) }
        let files = entries(m, includeFirmware: includeFirmware).filter { $0.kind == .file }
        if !exfat, let big = files.first(where: { $0.size > fat32Limit }) { return .fileTooBigForFAT32(big.path) }
        let needed = files.reduce(0) { $0 + $1.size } + Int64(files.count) * 65_536 + 1_048_576
        if let available, available < needed { return .notEnoughRoom(needed: needed, available: available) }
        return nil
    }

    public struct Outcome: Sendable {
        public var written: [String] = []
        public var failed: [String: String] = [:]
        public var checked = 0
        public var succeeded: Bool { failed.isEmpty }
    }

    /// Restores `snapshot` onto the card at `card`, after `check` passes.
    public static func restore(_ snapshot: URL, onto card: URL, includeFirmware: Bool = false,
                               onFile: @Sendable (String) -> Void = { _ in }) throws -> Outcome {
        let m = try Restorer(snapshot: snapshot).manifest
        let items = (try? FileManager.default.contentsOfDirectory(atPath: card.path)) ?? []
        let v = try? card.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey, .volumeAvailableCapacityKey])
        if let p = check(m, cardItems: items, filesystem: v?.volumeLocalizedFormatDescription,
                         available: v?.volumeAvailableCapacity.map(Int64.init), includeFirmware: includeFirmware) {
            throw p
        }
        let files = snapshot.appendingPathComponent("Files", isDirectory: true)
        var out = Outcome()
        var made: [URL] = []                      // only these are removed on a failure
        let list = entries(m, includeFirmware: includeFirmware)
        do {
            for e in list {
                try Task.checkCancellation()
                let target = card.appendingPathComponent(e.path)
                switch e.kind {
                case .folder:
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                        made.append(target)
                    }
                case .file:
                    onFile(e.path)
                    let temp = target.deletingLastPathComponent().appendingPathComponent(".mbu-restore-\(UUID().uuidString)")
                    made.append(temp)
                    let hash = try FileCopy.copy(files.appendingPathComponent(e.path), to: temp, size: e.size,
                                                 modified: e.modified, created: e.created, sparse: false)
                    guard hash == e.sha256 else {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
                            "\(e.path): the backup's copy doesn't match its manifest."])
                    }
                    try FileManager.default.moveItem(at: temp, to: target)
                    made[made.count - 1] = target
                    out.written.append(e.path)
                default:
                    break
                }
            }
        } catch {
            for u in made.reversed() { try? FileManager.default.removeItem(at: u) }
            throw error
        }
        // The whole card checked afterwards, file by file, against the manifest.
        for e in list where e.kind == .file {
            let got = try? Hashing.sha256(of: card.appendingPathComponent(e.path))
            if got?.hash == e.sha256, got?.size == e.size { out.checked += 1 }
            else { out.failed[e.path] = "It doesn't match the backup after writing." }
        }
        return out
    }
}

public extension CardRegister {
    /// The new card takes over `old`'s entry (B13): the same name and
    /// history; the old card's volume UUID kept as a previous identity.
    @discardableResult
    mutating func replace(_ old: Card, with v: VolumeInfo, now: Date = Date()) -> Card {
        guard let i = cards.firstIndex(where: { $0.id == old.id }) else { return old }
        if let previous = cards[i].volumeUUID { cards[i].previousVolumeUUIDs.append(previous) }
        cards[i].replaces = old.id
        return confirm(cards[i], is: v, now: now)
    }
}
