import AppKit
import Observation
import MacintoshBackupKit

/// The window's state and its jobs (W1-W14). The work (scanning,
/// copying, verifying, restoring) is the library's, run off the main
/// thread; this only wires it to the window.
@MainActor @Observable
final class AppModel {
    /// Where a backup stands (brief §12): one state, not scattered flags.
    enum State: Equatable {
        case waiting                          // for a card
        case scanning
        case ready                            // scanned: Back Up Now
        case confirming                       // the backup sheet
        case backingUp
        case finished(Manifest.Status)
        case failed(String)
    }

    var prefs = Preferences.load() { didSet { prefs.save(); reload() } }
    var repository: Repository { prefs.repository }

    // The card.
    var state = State.waiting
    var source: SourceDetails?
    var inventory: Inventory?
    var scanProblem: String?

    // The job.
    var progress: BackupProgress?
    var lastResult: BackupResult?
    private var task: Task<Void, Never>?

    // The history.
    var catalog: Catalog?
    var catalogProblem: String?
    var selection: String?                    // a snapshot's folder name
    var selectedManifest: Manifest?
    var pins: Set<UUID> = []

    // Verifying a snapshot (W8).
    var verifying = false
    var verifyingFile: String?
    var verification: Verification?

    var running: Bool { state == .backingUp || verifying }

    init() { reload() }

    // MARK: The history

    func reload() {
        // No backup folder yet: an empty history (it's made by the first backup).
        guard FileManager.default.fileExists(atPath: repository.root.path) else {
            catalog = Catalog(updated: Date(), snapshots: [])
            catalogProblem = nil
            pins = []
            select(nil)
            return
        }
        do {
            catalog = try Catalog.load(repository)
            catalogProblem = nil
        } catch let e as BackupError {
            catalog = nil
            catalogProblem = e.message
        } catch {
            catalog = nil
            catalogProblem = error.localizedDescription
        }
        pins = repository.pins()
        select(selection)
    }

    var restorePoints: [Catalog.Summary] { (catalog?.restorePoints ?? []).reversed() }
    var incomplete: [Catalog.Summary] { catalog?.incomplete ?? [] }

    func summary(_ folder: String?) -> Catalog.Summary? { catalog?.snapshots.first { $0.folder == folder } }

    func select(_ folder: String?) {
        selection = folder
        verification = nil
        guard let folder, let s = summary(folder), s.isRestorePoint else { selectedManifest = nil; return }
        selectedManifest = try? Manifest.read(repository.snapshots.appendingPathComponent(folder)
            .appendingPathComponent(Manifest.fileName))
    }

    func folderURL(_ s: Catalog.Summary) -> URL { repository.snapshots.appendingPathComponent(s.folder, isDirectory: true) }

    // MARK: The card (W3: chosen; Stage 4 recognises it)

    func chooseCard() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the BlueSCSI card (or a folder) to back up."
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { setSource(url) }
    }

    func setSource(_ url: URL) {
        source = SourceDetails.of(url)
        inventory = nil
        scanProblem = nil
        lastResult = nil
        state = .scanning
        Task {
            let result = await Task.detached { () -> Result<Inventory, Error> in
                Result { try Inventory.scan(url) }
            }.value
            guard source?.url == url else { return }
            switch result {
            case .success(let inv): inventory = inv; state = .ready
            case .failure(let e): scanProblem = (e as? BackupError)?.message ?? e.localizedDescription; state = .failed(scanProblem!)
            }
        }
    }

    func forgetCard() {
        guard !running else { return }
        source = nil; inventory = nil; scanProblem = nil; state = .waiting
    }

    // What the scan found (W1, W13).
    var images: [Entry] { inventory?.files.filter { $0.category == .diskImage } ?? [] }
    var configuration: [Entry] { inventory?.files.filter { $0.category == .configuration || $0.category == .log } ?? [] }
    var warnings: [String] {
        guard let inv = inventory else { return [] }
        var w = inv.entries.compactMap { e -> String? in
            if let note = e.note { return "\(e.path): \(note)" }
            if e.kind == .link { return "\(e.path): a symbolic link, which won't be copied." }
            if e.kind == .other { return "\(e.path): not a file or folder, so it won't be copied." }
            return nil
        }
        w += inv.notCleanlyShutDown.map { Inventory.uncleanWarning($0.path) }
        if inv.files.contains(where: { $0.category == .firmware }) {
            w.append("The card holds a BlueSCSI firmware update package; it's backed up like everything else.")
        }
        return w
    }
    var neededBytes: Int64 { (inventory?.totalBytes ?? 0) + 16 * 1_048_576 }
    var freeBytes: Int64? { repository.availableBytes }

    // MARK: Backing up (W4-W6)

    func askToBackUp() {
        guard state == .ready || isFinished, inventory != nil else { return }
        state = .confirming
    }

    var isFinished: Bool { if case .finished = state { return true }; return false }

    func cancelConfirmation() { state = inventory == nil ? .waiting : .ready }

    func backUp() {
        guard let source else { return }
        state = .backingUp
        progress = BackupProgress(stage: .scanning)
        lastResult = nil
        var writer = SnapshotWriter(repository: repository)
        writer.thinning = prefs.thinning
        let url = source.url
        let report: @Sendable (BackupProgress) -> Void = { [weak self] p in
            Task { @MainActor in if self?.state == .backingUp { self?.progress = p } }
        }
        let job = writer
        task = Task {
            let result = await Task.detached { () -> Result<BackupResult, Error> in
                do { return .success(try await job.backup(url, onProgress: report)) }
                catch { return .failure(error) }
            }.value
            progress = nil
            switch result {
            case .success(let r):
                lastResult = r
                state = .finished(r.manifest.status)
                reload()
                if r.verified { select(r.folder.lastPathComponent) }
            case .failure(let e):
                state = .failed((e as? BackupError)?.message ?? e.localizedDescription)
                reload()
            }
            // Ready to back up again (the card is still there).
        }
    }

    func cancel() { task?.cancel() }

    // MARK: Verifying (W8)

    func verifySelected() {
        guard let s = summary(selection), s.isRestorePoint else { return }
        let url = folderURL(s)
        verifying = true
        verification = nil
        let onFile: @Sendable (String) -> Void = { [weak self] file in
            Task { @MainActor in self?.verifyingFile = file }
        }
        Task {
            let result = await Task.detached { () -> Result<Verification, Error> in
                Result { try Verifier.verify(url, onFile: onFile) }
            }.value
            verifying = false
            verifyingFile = nil
            switch result {
            case .success(let v): verification = v
            case .failure(let e): verificationProblem = (e as? BackupError)?.message ?? e.localizedDescription
            }
        }
    }
    var verificationProblem: String?

    // MARK: Deleting, pinning, clearing (W9, W10, W14)

    func togglePin(_ s: Catalog.Summary) {
        guard let id = s.snapshotID else { return }
        try? repository.setPinned(id, !pins.contains(id))
        pins = repository.pins()
    }

    /// The card's last restore point? (W9's extra warning.)
    func isLast(_ s: Catalog.Summary) -> Bool {
        ((try? repository.otherRestorePoints(than: s.folder, volumeUUID: s.volumeUUID)) ?? []).isEmpty
    }

    func delete(_ s: Catalog.Summary) {
        do {
            try repository.delete(folder: s.folder, id: s.snapshotID, confirmed: true)
            if selection == s.folder { selection = nil }
        } catch let e as Repository.DeleteError {
            show("The snapshot couldn't be deleted", e.message)
        } catch {
            show("The snapshot couldn't be deleted", error.localizedDescription)
        }
        reload()
    }

    func clearIncomplete() {
        for s in incomplete { _ = try? repository.delete(folder: s.folder, id: s.snapshotID, confirmed: true) }
        reload()
    }

    // MARK: Folders

    func openBackupFolder() {
        try? repository.prepare()
        NSWorkspace.shared.open(repository.root)
    }

    func reveal(_ s: Catalog.Summary) { NSWorkspace.shared.activateFileViewerSelecting([folderURL(s)]) }

    func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose the folder to keep backups in."
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { prefs.repositoryPath = url.path }
    }

    func useDefaultBackupFolder() { prefs.repositoryPath = nil }

    func show(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: Words

func bytes(_ n: Int64?) -> String {
    guard let n else { return "—" }
    return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

func when(_ d: Date?) -> String {
    guard let d else { return "—" }
    return d.formatted(date: .abbreviated, time: .shortened)
}
