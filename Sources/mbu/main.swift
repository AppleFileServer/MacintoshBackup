import Foundation
import MacintoshBackupKit

// mbu: the Macintosh Backup Utility's developer tool (Stage 1).
//   mbu backup <source folder> [--repository <folder>]
//   mbu verify <snapshot folder>

var args = Array(CommandLine.arguments.dropFirst())
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: mbu backup <source> [--repository <folder>] | mbu verify <snapshot>\n".utf8))
    exit(2)
}
var repository = Repository()
if let i = args.firstIndex(of: "--repository"), i + 1 < args.count {
    repository = Repository(root: URL(fileURLWithPath: args[i + 1]))
    args.removeSubrange(i...(i + 1))
}
guard args.count == 2 else { usage() }
let target = URL(fileURLWithPath: args[1])

switch args[0] {
case "backup":
    do {
        final class Last: @unchecked Sendable { var path: String? }
        let last = Last()
        let r = try await SnapshotWriter(repository: repository).backup(target) { p in
            if p.stage != .copying { print("  \(p.stage.rawValue)") }
            else if let c = p.current, c != last.path {
                last.path = c
                print("  copying \(p.filesDone + 1) of \(p.filesTotal): \(c)")
            }
        }
        let m = r.manifest
        print("\(m.status.rawValue): \(m.name), \(m.totals.files) files, \(m.totals.folders) folders, \(m.totals.bytes) bytes")
        print("  \(r.folder.path)")
        for w in m.warnings { print("  note: \(w)") }
        for e in m.entries where e.result == .failed || e.result == .changed {
            print("  \(e.result!.rawValue): \(e.path): \(e.note ?? "")")
        }
        exit(r.verified ? 0 : 1)
    } catch let e as BackupError {
        print("error: \(e.message)"); exit(1)
    }
case "verify":
    do {
        let v = try Verifier.verify(target)
        print("\(v.passed ? "passed" : "FAILED"): \(v.manifest.name), \(v.filesChecked) files checked")
        for p in v.problems { print("  \(p.kind.rawValue): \(p.path)") }
        exit(v.passed ? 0 : 1)
    } catch let e as BackupError {
        print("error: \(e.message)"); exit(1)
    }
default:
    usage()
}
