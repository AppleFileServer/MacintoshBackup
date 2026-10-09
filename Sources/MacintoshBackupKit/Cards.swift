import DiskArbitration
import Foundation

/// A mounted disk, as far as the app needs to know it (C1, C3): read
/// from the volume's own properties and DiskArbitration, never written.
public struct VolumeInfo: Sendable, Equatable {
    public var url: URL
    public var name: String?
    public var uuid: String?
    public var capacity: Int64?
    public var filesystem: String?
    public var isRemovable = false
    public var isEjectable = false
    public var isInternal = false
    public var deviceModel: String?

    public init(url: URL, name: String? = nil, uuid: String? = nil, capacity: Int64? = nil, filesystem: String? = nil,
                isRemovable: Bool = false, isEjectable: Bool = false, isInternal: Bool = false, deviceModel: String? = nil) {
        self.url = url; self.name = name; self.uuid = uuid; self.capacity = capacity; self.filesystem = filesystem
        self.isRemovable = isRemovable; self.isEjectable = isEjectable; self.isInternal = isInternal
        self.deviceModel = deviceModel
    }

    /// External, and removable or ejectable: the only disks considered (C1).
    public var isCandidate: Bool { (isRemovable || isEjectable) && !isInternal }

    public static func of(_ url: URL) -> VolumeInfo {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey,
                                                  .volumeLocalizedFormatDescriptionKey, .volumeIsRemovableKey,
                                                  .volumeIsEjectableKey, .volumeIsInternalKey])
        var info = VolumeInfo(url: url, name: v?.volumeName, uuid: v?.volumeUUIDString,
                              capacity: v?.volumeTotalCapacity.map(Int64.init),
                              filesystem: v?.volumeLocalizedFormatDescription,
                              isRemovable: v?.volumeIsRemovable ?? false, isEjectable: v?.volumeIsEjectable ?? false,
                              isInternal: v?.volumeIsInternal ?? false)
        if let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
           let d = DADiskCopyDescription(disk) as? [String: Any] {
            info.deviceModel = (d[kDADiskDescriptionDeviceModelKey as String] as? String)?
                .trimmingCharacters(in: .whitespaces)
        }
        return info
    }
}

/// How far a disk looks like a BlueSCSI card (C2), from its top-level
/// file list and the start of its log: read only.
public enum Evidence: String, Sendable, Comparable {
    case none, likely, strong
    public static func < (a: Evidence, b: Evidence) -> Bool {
        [Evidence.none, .likely, .strong].firstIndex(of: a)! < [Evidence.none, .likely, .strong].firstIndex(of: b)!
    }

    public static func of(_ root: URL) -> Evidence {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return .none }
        let lower = Set(names.map { $0.lowercased() })
        if lower.contains("bluescsi.ini") { return .strong }
        for log in ["log.txt", "lastlog.txt"] where lower.contains(log) {
            let name = names.first { $0.lowercased() == log }!
            if let h = try? FileHandle(forReadingFrom: root.appendingPathComponent(name)),
               let d = try? h.read(upToCount: 1024) {
                try? h.close()
                if String(decoding: d, as: UTF8.self).range(of: "bluescsi", options: .caseInsensitive) != nil { return .strong }
            }
        }
        if names.contains(where: { !$0.hasPrefix(".") && Category.isImageName($0) }) { return .likely }
        return .none
    }
}

/// A registered card (C3): its friendly name, and how it's recognised.
public struct Card: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var volumeUUID: String?
    public var volumeName: String?
    public var capacity: Int64?
    public var filesystem: String?
    public var deviceModel: String?
    public var firstSeen: Date
    public var lastSeen: Date
    /// The card this one took over from (B13's replacement), if any.
    public var replaces: UUID?
    /// The volume UUIDs it had before (a replaced or reformatted card).
    public var previousVolumeUUIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, name, volumeUUID, volumeName, capacity, filesystem, deviceModel, firstSeen, lastSeen, replaces,
             previousVolumeUUIDs
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        volumeUUID = try c.decodeIfPresent(String.self, forKey: .volumeUUID)
        volumeName = try c.decodeIfPresent(String.self, forKey: .volumeName)
        capacity = try c.decodeIfPresent(Int64.self, forKey: .capacity)
        filesystem = try c.decodeIfPresent(String.self, forKey: .filesystem)
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        replaces = try c.decodeIfPresent(UUID.self, forKey: .replaces)
        previousVolumeUUIDs = try c.decodeIfPresent([String].self, forKey: .previousVolumeUUIDs) ?? []
    }
    init(id: UUID, name: String, volumeUUID: String?, volumeName: String?, capacity: Int64?, filesystem: String?,
         deviceModel: String?, firstSeen: Date, lastSeen: Date, replaces: UUID?) {
        self.id = id; self.name = name; self.volumeUUID = volumeUUID; self.volumeName = volumeName
        self.capacity = capacity; self.filesystem = filesystem; self.deviceModel = deviceModel
        self.firstSeen = firstSeen; self.lastSeen = lastSeen; self.replaces = replaces
    }
}

/// The card register, Catalog/cards.json (C3). Many cards; the window is
/// designed for one.
public struct CardRegister: Codable, Sendable, Equatable {
    public enum Match: Sendable, Equatable {
        case known(Card)              // the same volume UUID
        case probably(Card)           // the same name, size and format; a new UUID: ask
        case new
    }

    public var cards: [Card] = []
    public init() {}

    static func url(_ r: Repository) -> URL { r.catalog.appendingPathComponent("cards.json") }

    public static func load(_ r: Repository) -> CardRegister {
        guard let d = try? Data(contentsOf: url(r)),
              let c = try? Manifest.decoder.decode(CardRegister.self, from: d) else { return CardRegister() }
        return c
    }

    public func save(_ r: Repository) throws {
        try r.prepare()
        try Manifest.encoder.encode(self).write(to: CardRegister.url(r), options: .atomic)
    }

    public func match(_ v: VolumeInfo) -> Match {
        if let uuid = v.uuid, let c = cards.first(where: { $0.volumeUUID == uuid }) { return .known(c) }
        if let uuid = v.uuid, let c = cards.first(where: { $0.previousVolumeUUIDs.contains(uuid) }) { return .probably(c) }
        if let c = cards.first(where: { c in
            c.volumeName != nil && c.volumeName == v.name && c.filesystem == v.filesystem
                && c.capacity != nil && v.capacity != nil && abs(c.capacity! - v.capacity!) <= c.capacity! / 100
        }) { return .probably(c) }
        return .new
    }

    /// Registers a new card under `name`.
    @discardableResult
    public mutating func register(_ v: VolumeInfo, name: String, now: Date = Date()) -> Card {
        let now = Manifest.milliseconds(now)            // as it's saved
        let c = Card(id: UUID(), name: name, volumeUUID: v.uuid, volumeName: v.name, capacity: v.capacity,
                     filesystem: v.filesystem, deviceModel: v.deviceModel, firstSeen: now, lastSeen: now, replaces: nil)
        cards.append(c)
        return c
    }

    /// The owner says this volume is `card` (a "probably" match, or a card
    /// reformatted): its details brought up to date.
    @discardableResult
    public mutating func confirm(_ card: Card, is v: VolumeInfo, now: Date = Date()) -> Card {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return card }
        cards[i].volumeUUID = v.uuid
        cards[i].volumeName = v.name
        cards[i].capacity = v.capacity
        cards[i].filesystem = v.filesystem
        cards[i].deviceModel = v.deviceModel ?? cards[i].deviceModel
        cards[i].lastSeen = Manifest.milliseconds(now)
        return cards[i]
    }

    public mutating func seen(_ card: Card, now: Date = Date()) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i].lastSeen = Manifest.milliseconds(now) }
    }

    public mutating func rename(_ card: Card, to name: String) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i].name = name }
    }
}

/// What to do about a disk appearing or going (C1, C4): pure, so it can
/// be tested with simulated mounts. One offer per insertion; nothing for
/// disks that aren't candidates or show no sign of BlueSCSI; never a
/// backup by itself.
public struct CardWatcher: Sendable {
    public enum Decision: Sendable, Equatable {
        case ignore
        case offer(VolumeInfo, Evidence, CardRegister.Match)
        case gone(URL)
    }

    private var offered: Set<String> = []
    public init() {}

    /// `evidence` is passed in (the app reads it off the main thread).
    public mutating func mounted(_ v: VolumeInfo, evidence: Evidence, register: CardRegister) -> Decision {
        guard v.isCandidate else { return .ignore }
        let match = register.match(v)
        if case .new = match, evidence == .none { return .ignore }
        let key = v.url.path + "|" + (v.uuid ?? "")
        guard offered.insert(key).inserted else { return .ignore }        // a duplicate notification
        return .offer(v, evidence, match)
    }

    public mutating func unmounted(_ url: URL) -> Decision {
        let before = offered.count
        offered = offered.filter { !$0.hasPrefix(url.path + "|") }
        return before == offered.count ? .ignore : .gone(url)
    }
}
