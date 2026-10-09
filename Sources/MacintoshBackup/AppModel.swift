import AppKit
import Observation
@preconcurrency import UserNotifications
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

    // Cards (Stage 4; C1-C6).
    var register = CardRegister()
    var card: Card?                           // the registered card being shown
    var volume: VolumeInfo?                   // the disk it's on, if offered
    var evidence: Evidence?
    /// A new card to register (the sheet), or a probable match to ask about.
    var registering: VolumeInfo?
    var asking: (VolumeInfo, Card)?
    var cardRemoved = false
    private var watcher = CardWatcher()
    private var monitor: VolumeMonitor?
    private var notified = false

    init() {
        reload()
        monitor = VolumeMonitor(mounted: { [weak self] in self?.mounted($0) },
                                unmounted: { [weak self] in self?.unmounted($0) })
    }

    // MARK: Cards appearing and going (C1-C5)

    func mounted(_ url: URL) {
        Task {
            let found = await Task.detached { () -> (VolumeInfo, Evidence) in
                let v = VolumeInfo.of(url)
                return (v, v.isCandidate ? Evidence.of(url) : .none)
            }.value
            guard case .offer(let v, let e, let match) = watcher.mounted(found.0, evidence: found.1, register: register)
            else { return }
            offer(v, evidence: e, match: match)
        }
    }

    func unmounted(_ url: URL) {
        _ = watcher.unmounted(url)
        guard source?.url.standardizedFileURL == url.standardizedFileURL else { return }
        if state == .backingUp {
            cardRemoved = true
            cancel()
        } else if !running {
            forgetCard()
        }
    }

    /// A card is here (C4): shown, scanned (reading only), and the owner
    /// asked to register it if it's new; never backed up by itself.
    func offer(_ v: VolumeInfo, evidence e: Evidence, match: CardRegister.Match) {
        guard !running, state != .confirming else { return }
        volume = v
        evidence = e
        switch match {
        case .known(let c):
            card = c
            register.seen(c)
            try? register.save(repository)
        case .probably(let c):
            card = nil
            asking = (v, c)
        case .new:
            card = nil
            registering = v
        }
        setSource(v.url)
        notifyIfInBackground()
    }

    func registerCard(_ name: String) {
        guard let v = registering else { return }
        card = register.register(v, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mac Plus BlueSCSI" : name)
        try? register.save(repository)
        registering = nil
    }

    func notNow() { registering = nil }

    func answerProbable(same: Bool) {
        guard let (v, c) = asking else { return }
        asking = nil
        if same {
            card = register.confirm(c, is: v)
            try? register.save(repository)
        } else {
            registering = v
        }
    }

    /// A snapshot's card, by name: its own record, or the registered card
    /// with its volume's UUID (a snapshot made before registering).
    func cardName(of s: Catalog.Summary) -> String {
        s.cardName ?? register.cards.first { $0.volumeUUID != nil && $0.volumeUUID == s.volumeUUID }?.name
            ?? s.volumeName ?? "—"
    }

    var cardName: String { card?.name ?? source?.volumeName ?? source?.url.lastPathComponent ?? "The card" }

    /// One notification if the app is in the background (C4).
    func notifyIfInBackground() {
        guard !NSApp.isActive else { return }
        let centre = UNUserNotificationCenter.current()
        let name = cardName
        centre.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) is connected"
            content.body = "Open the Macintosh Backup Utility to back it up."
            centre.add(UNNotificationRequest(identifier: "card-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    /// Ejects the card properly (C5); not while a job is running.
    func eject() {
        guard !running, let url = source?.url else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            show("The card couldn't be ejected", error.localizedDescription + " Close anything using it, and try again, or eject it in the Finder.")
        }
    }

    var canEject: Bool { !running && volume != nil && source?.url == volume?.url }

    // MARK: The history

    func reload() {
        register = CardRegister.load(repository)
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
        cardRemoved = false
        if volume?.url != url { volume = nil; card = nil; evidence = nil }
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
        volume = nil; card = nil; evidence = nil; registering = nil; asking = nil
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
        writer.card = card
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
                if cardRemoved { self.source = nil; inventory = nil; volume = nil }
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
        ((try? repository.otherRestorePoints(than: s.folder, volumeUUID: s.volumeUUID, cardID: s.cardID)) ?? []).isEmpty
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
