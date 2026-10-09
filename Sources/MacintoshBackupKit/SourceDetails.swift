import Foundation

/// What's known of the chosen card (W1): its volume, read without writing.
public struct SourceDetails: Sendable, Equatable {
    public var url: URL
    public var volumeName: String?
    public var volumeUUID: String?
    public var filesystem: String?
    public var capacity: Int64?
    public var available: Int64?
    public var isRemovable: Bool?

    public var used: Int64? { capacity.flatMap { c in available.map { c - $0 } } }

    public static func of(_ url: URL) -> SourceDetails {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey, .volumeLocalizedFormatDescriptionKey,
                                                  .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                  .volumeIsRemovableKey])
        return SourceDetails(url: url, volumeName: v?.volumeName, volumeUUID: v?.volumeUUIDString,
                             filesystem: v?.volumeLocalizedFormatDescription,
                             capacity: v?.volumeTotalCapacity.map(Int64.init),
                             available: v?.volumeAvailableCapacity.map(Int64.init),
                             isRemovable: v?.volumeIsRemovable)
    }
}
