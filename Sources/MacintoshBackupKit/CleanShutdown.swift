import Foundation

/// Whether a disk image's HFS volume was put away properly (W13), read
/// from the image without changing it: through the Apple partition map
/// (driver descriptor "ER" at block 0, entries "PM" from block 1) to the
/// Apple_HFS partition, or, for an image with no map (a floppy's), the
/// volume at its start; then the volume header 1024 bytes in: HFS's
/// master directory block ("BD", attributes at byte 10) or HFS Plus's
/// header ("H+"/"HX", attributes at byte 4). Bit 8 of the attributes is
/// "the volume was unmounted cleanly" (Inside Macintosh: Files; TN1150).
/// PROVISIONAL: that System 6 clears it while a disk is in use, so that
/// a disk that lost power shows it clear, is to be confirmed on the
/// owner's card (Stage 4).
public enum CleanShutdown: String, Codable, Sendable {
    case clean, notClean, unknown

    static let unmountedBit: UInt32 = 1 << 8

    public static func check(_ url: URL) -> CleanShutdown {
        guard let h = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? h.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? h.seek(toOffset: offset)) != nil, let d = try? h.read(upToCount: count),
                  d.count == count else { return nil }
            return d
        }
        func u16(_ d: Data, _ at: Int) -> UInt32 { UInt32(d[d.startIndex + at]) << 8 | UInt32(d[d.startIndex + at + 1]) }
        func u32(_ d: Data, _ at: Int) -> UInt32 { u16(d, at) << 16 | u16(d, at + 2) }

        var volume: UInt64 = 0
        if let block0 = read(0, 512), block0.prefix(2) == Data("ER".utf8) {
            let blockSize = UInt64(max(512, u16(block0, 2)))
            guard let first = read(512, 512), first.prefix(2) == Data("PM".utf8) else { return .unknown }
            let count = min(u32(first, 4), 64)
            var found = false
            for i in 0..<UInt64(count) {
                guard let e = read(512 + i * 512, 512), e.prefix(2) == Data("PM".utf8) else { break }
                let type = String(decoding: e[(e.startIndex + 48)..<(e.startIndex + 80)].prefix { $0 != 0 }, as: UTF8.self)
                if type == "Apple_HFS" {
                    volume = UInt64(u32(e, 8)) * blockSize
                    found = true
                    break
                }
            }
            guard found else { return .unknown }
        }
        guard let header = read(volume + 1024, 512) else { return .unknown }
        let sig = header.prefix(2)
        let attributes: UInt32
        if sig == Data("BD".utf8) { attributes = u16(header, 10) }
        else if sig == Data("H+".utf8) || sig == Data("HX".utf8) { attributes = u32(header, 4) }
        else { return .unknown }
        return attributes & unmountedBit != 0 ? .clean : .notClean
    }
}
