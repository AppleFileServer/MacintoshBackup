import Foundation

/// A snapshot checked against its own manifest, later (brief §7): every
/// file there, its size and SHA-256 as recorded, every folder there,
/// nothing unexplained. Reads only; changes nothing.
public struct Verification: Sendable {
    public struct Problem: Sendable, Equatable {
        public enum Kind: String, Sendable { case missing, wrongSize, wrongChecksum, unreadable, unexpected }
        public let path: String
        public let kind: Kind
    }
    public let manifest: Manifest
    public let problems: [Problem]
    public let filesChecked: Int
    public var passed: Bool { problems.isEmpty && manifest.status == .verified }
}

public enum Verifier {
    public static func verify(_ snapshot: URL, onFile: @Sendable (String) -> Void = { _ in }) throws -> Verification {
        let m = try Manifest.read(snapshot.appendingPathComponent(Manifest.fileName))
        let files = snapshot.appendingPathComponent("Files", isDirectory: true)
        var problems: [Verification.Problem] = []
        var checked = 0
        var known = Set<String>()
        for e in m.entries {
            known.insert(e.path)
            let url = files.appendingPathComponent(e.path)
            switch e.kind {
            case .folder:
                var dir: ObjCBool = false
                if !FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) || !dir.boolValue {
                    problems.append(.init(path: e.path, kind: .missing))
                }
            case .file where e.result == .verified:
                onFile(e.path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    problems.append(.init(path: e.path, kind: .missing)); continue
                }
                guard let got = try? Hashing.sha256(of: url) else {
                    problems.append(.init(path: e.path, kind: .unreadable)); continue
                }
                checked += 1
                if got.size != e.size { problems.append(.init(path: e.path, kind: .wrongSize)) }
                else if got.hash != e.sha256 { problems.append(.init(path: e.path, kind: .wrongChecksum)) }
            default:
                break
            }
        }
        // Anything in the snapshot the manifest doesn't account for.
        if let walker = FileManager.default.enumerator(at: files, includingPropertiesForKeys: nil, options: []) {
            let prefix = files.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            for case let url as URL in walker {
                let full = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard full.hasPrefix(prefix) else { continue }
                let path = String(full.dropFirst(prefix.count))
                if !known.contains(path) { problems.append(.init(path: path, kind: .unexpected)) }
            }
        }
        return Verification(manifest: m, problems: problems, filesChecked: checked)
    }
}
