import Foundation
import MacintoshBackupKit

// mbu: the Macintosh Backup Utility's developer tool (Stages 1-2).
//   mbu backup <source folder>             a new snapshot
//   mbu verify <snapshot folder>           checked against its manifest
//   mbu list                               the catalogue
//   mbu rebuild                            the catalogue rebuilt from the manifests
//   mbu show <snapshot folder>             its manifest
//   mbu restore <snapshot folder> <destination folder> [<path> ...] [--skip|--keep-both|--replace]
//       (no paths: the whole snapshot, into a new folder in the destination)
// each with [--repository <folder>] (default ~/Mac Plus Backups)

var args = Array(CommandLine.arguments.dropFirst())
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: mbu backup <source> | verify <snapshot> | list | rebuild | show <snapshot> | restore <snapshot> <destination> [<path> ...] [--skip|--keep-both|--replace]; [--repository <folder>]\n".utf8))
    exit(2)
}
var repository = Repository()
if let i = args.firstIndex(of: "--repository"), i + 1 < args.count {
    repository = Repository(root: URL(fileURLWithPath: args[i + 1]))
    args.removeSubrange(i...(i + 1))
}
var policy = Restorer.Conflict.skip
for (flag, p) in [("--skip", Restorer.Conflict.skip), ("--keep-both", .keepBoth), ("--replace", .replace)] {
    if let i = args.firstIndex(of: flag) { policy = p; args.remove(at: i) }
}
guard let command = args.first else { usage() }

func summaries(_ c: Catalog) {
    for s in c.snapshots {
        let mark = s.isRestorePoint ? "verified " : (s.status?.rawValue ?? "unreadable").padding(toLength: 9, withPad: " ", startingAt: 0)
        print("\(mark) \(s.folder)  \(s.files) files, \(s.bytes) bytes (\(s.storedBytes) stored)  \(s.volumeName ?? "")\(s.problem.map { "  " + $0 } ?? "")")
    }
    print("\(c.restorePoints.count) restore point(s); \(c.incomplete.count) incomplete")
}

switch command {
case "list", "rebuild":
    do { summaries(command == "list" ? try Catalog.load(repository) : try Catalog.rebuild(repository)); exit(0) }
    catch let e as BackupError { print("error: \(e.message)"); exit(1) }
case "show":
    guard args.count == 2 else { usage() }
    do {
        let m = try Manifest.read(URL(fileURLWithPath: args[1]).appendingPathComponent(Manifest.fileName))
        print("\(m.name)  \(m.status.rawValue)  \(m.source.volumeName ?? m.source.path)")
        for e in m.entries {
            print("  \(e.kind.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(e.category.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(e.result?.rawValue ?? "")  \(e.path)  \(e.kind == .file ? "\(e.size)" : "")")
        }
        exit(0)
    } catch let e as BackupError { print("error: \(e.message)"); exit(1) }
case "restore":
    guard args.count >= 3 else { usage() }
    do {
        let r = try Restorer(snapshot: URL(fileURLWithPath: args[1]))
        let paths = args.count > 3 ? Array(args[3...]) : nil
        var dest = URL(fileURLWithPath: args[2])
        if paths == nil { dest = try r.newFolder(in: dest) }
        let chosen = policy
        let o = try r.restore(paths, into: dest, conflict: { _ in chosen })
        print("\(o.succeeded ? "restored" : "FAILED"): \(o.restored.count) file(s) into \(o.destination.path)")
        for (p, n) in o.renamed { print("  kept both: \(p) as \(n)") }
        for p in o.skipped { print("  skipped (already there): \(p)") }
        for (p, why) in o.failed { print("  failed: \(p): \(why)") }
        exit(o.succeeded ? 0 : 1)
    } catch let e as BackupError { print("error: \(e.message)"); exit(1) }
default:
    break
}

guard args.count == 2 else { usage() }
let target = URL(fileURLWithPath: args[1])

switch command {
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
