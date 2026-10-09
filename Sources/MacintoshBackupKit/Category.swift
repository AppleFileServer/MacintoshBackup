import Foundation

/// What a file on a BlueSCSI card is, from its name (B3, B8, B13).
public enum Category: String, Codable, Sendable {
    case diskImage, configuration, log, firmware, macOSMetadata, other

    /// macOS's own files and folders on a FAT card (SPECIFICATION.md §20.1).
    static let macOSNames: Set<String> = [".DS_Store", ".fseventsd", ".Spotlight-V100", ".Trashes",
                                          ".TemporaryItems", ".VolumeIcon.icns", ".apdisk",
                                          ".metadata_never_index", ".DocumentRevisions-V100"]
    /// BlueSCSI's device codes (its firmware's findHDDImages).
    static let deviceCodes = ["hd", "cd", "fd", "mo", "re", "tp", "zp"]

    /// `path` is relative to the card's root, "/" between folders.
    public static func of(path: String, isFolder: Bool = false) -> Category {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { return .other }
        if parts.contains(where: { macOSNames.contains($0) }) || name.hasPrefix("._") { return .macOSMetadata }
        if isFolder { return .other }
        let lower = name.lowercased()
        if lower == "bluescsi.ini" { return .configuration }
        if lower == "log.txt" || lower == "lastlog.txt" { return .log }
        if lower.hasPrefix("bluescsi"), lower.hasSuffix(".zip") || lower.hasSuffix(".bin") { return .firmware }
        if isImageName(name) { return .diskImage }
        return .other
    }

    /// A BlueSCSI image name: a device code, then an ID digit, "_" or "."
    /// ("HD60_512 Transfer.hda", "CD3.iso", "HD_512.hda"), at most 64
    /// characters. "readme.txt" isn't one.
    public static func isImageName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard name.count <= 64, deviceCodes.contains(where: { lower.hasPrefix($0) }) else { return false }
        let rest = lower.dropFirst(2)
        guard let next = rest.first else { return false }
        return next.isNumber || next == "_" || next == "."
    }
}
