import Foundation

/// A snapshot's own record of what it holds (B6; ARCHITECTURE.md), in
/// its folder as SnapshotManifest.json. Never rewritten once complete.
public struct Manifest: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case verified, inconsistent, failed, cancelled }
    public struct App: Codable, Sendable, Equatable { public var name: String; public var version: String }
    public struct Source: Codable, Sendable, Equatable {
        public var path: String
        public var volumeName: String?
        public var volumeUUID: String?
        public var filesystem: String?
        public var capacity: Int64?
        /// The registered card (C3), if it was registered.
        public var cardID: UUID?
        public var cardName: String?
    }
    public struct Totals: Codable, Sendable, Equatable {
        public var files: Int
        public var folders: Int
        public var bytes: Int64
    }

    public static let schema = 1
    public static let fileName = "SnapshotManifest.json"

    public var schemaVersion: Int
    public var snapshotID: UUID
    public var name: String
    public var status: Status
    public var started: Date
    public var finished: Date
    public var app: App
    public var source: Source
    public var totals: Totals
    public var entries: [Entry]
    public var warnings: [String]

    /// Dates in ISO 8601 with fractions of a second, so a date read back is
    /// the date written (whole seconds are read too).
    public static func milliseconds(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    /// "2026-10-09T16:35:30.622Z", the milliseconds from a whole number
    /// (a formatter's own arithmetic can be a millisecond out).
    static func dateText(_ d: Date) -> String {
        let ms = Int64((d.timeIntervalSince1970 * 1000).rounded())
        let seconds = Date(timeIntervalSince1970: Double(ms.quotientRoundingDown(1000)))
        let whole = seconds.formatted(Date.ISO8601FormatStyle())          // "...:30Z"
        return String(whole.dropLast()) + String(format: ".%03lldZ", ms - ms.quotientRoundingDown(1000) * 1000)
    }
    static func date(_ s: String) -> Date? {
        let d = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s))
            ?? (try? Date.ISO8601FormatStyle().parse(s))
        return d.map(milliseconds)
    }
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { d, enc in
            var c = enc.singleValueContainer()
            try c.encode(dateText(d))
        }
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = date(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a date: \(s)")
            }
            return date
        }
        return d
    }

    public func encoded() throws -> Data { try Manifest.encoder.encode(self) }

    /// Reads a manifest, and checks it's whole: a known schema, and totals
    /// that agree with its entries. Treated as data only (brief §9).
    public static func read(_ url: URL) throws -> Manifest {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw BackupError.manifestInvalid("it can't be read") }
        let m: Manifest
        do { m = try decoder.decode(Manifest.self, from: data) } catch {
            throw BackupError.manifestInvalid("it isn't a manifest (\(error.localizedDescription))")
        }
        guard m.schemaVersion >= 1 else { throw BackupError.manifestInvalid("schema \(m.schemaVersion)") }
        let files = m.entries.filter { $0.kind == .file }
        guard files.count == m.totals.files, files.reduce(0, { $0 + $1.size }) == m.totals.bytes else {
            throw BackupError.manifestInvalid("its totals don't match its files")
        }
        return m
    }
}

extension Int64 {
    /// Division rounding towards minus infinity (for dates before 1970).
    func quotientRoundingDown(_ d: Int64) -> Int64 {
        let q = self / d
        return (self % d != 0 && (self < 0) != (d < 0)) ? q - 1 : q
    }
}
