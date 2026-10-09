import AppKit
import SwiftUI
import MacintoshBackupKit

/// Before a backup (W4): what will be copied, the room it needs, the
/// warnings; Back Up is the owner's confirmation.
struct BackupSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Back up \(model.source?.volumeName ?? "the card")?").font(.title3.bold())
            if let inv = model.inventory {
                Text("\(inv.files.count) files (\(model.images.count) disk image\(model.images.count == 1 ? "" : "s")), \(bytes(inv.totalBytes)), copied into a new snapshot and every file checked. Nothing is written to the card.")
            }
            HStack {
                Text("Room needed: about \(bytes(model.neededBytes))")
                Spacer()
                Text("Free: \(bytes(model.freeBytes))")
            }
            .font(.callout).foregroundStyle(.secondary)
            if let free = model.freeBytes, free < model.neededBytes {
                Label("There isn't room for this backup in the backup folder. Free some space, or choose another folder in Settings.",
                      systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            if !model.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                }
            }
            if model.prefs.thinning {
                Text("Afterwards, older snapshots of this card are thinned (Settings).").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelConfirmation() }.keyboardShortcut(.cancelAction)
                Button("Back Up") { model.backUp() }
                    .keyboardShortcut(.defaultAction)
                    .disabled((model.freeBytes ?? .max) < model.neededBytes)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Restoring (W7): the whole snapshot into a new folder, or chosen files
/// and folders into a folder; each conflict asked.
struct RestoreSheet: View {
    @Bindable var model: AppModel
    let summary: Catalog.Summary
    @Environment(\.dismiss) private var dismiss

    @State private var whole = true
    @State private var chosen: Set<String> = []
    @State private var destination: URL?
    @State private var running = false
    @State private var current: String?
    @State private var outcome: Restorer.Outcome?
    @State private var problem: String?

    var manifest: Manifest? { try? Manifest.read(model.folderURL(summary).appendingPathComponent(Manifest.fileName)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from \(summary.name)").font(.title3.bold())
            Picker("", selection: $whole) {
                Text("The whole snapshot, into a new folder").tag(true)
                Text("Chosen files and folders").tag(false)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            if !whole, let m = manifest {
                List(m.entries.filter { $0.result == .verified }) { e in
                    Toggle(isOn: Binding(get: { chosen.contains(e.path) }, set: { on in if on { chosen.insert(e.path) } else { chosen.remove(e.path) } })) {
                        HStack {
                            Image(systemName: e.kind == .folder ? "folder" : (e.category == .diskImage ? "internaldrive" : "doc"))
                            Text(e.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if e.kind == .file { Text(bytes(e.size)).foregroundStyle(.secondary) }
                        }
                    }
                }
                .frame(height: 200)
            }
            HStack {
                Text("Into:")
                Text(destination?.path ?? "choose a folder").foregroundStyle(destination == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { choose() }.disabled(running)
            }
            if running { HStack { ProgressView().controlSize(.small); Text(current ?? "").font(.caption).lineLimit(1) } }
            if let o = outcome {
                Label(o.succeeded ? "Restored \(o.restored.count) file\(o.restored.count == 1 ? "" : "s"), each checked against the backup." : "\(o.failed.count) file(s) couldn't be restored.",
                      systemImage: o.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(o.succeeded ? .green : .red)
                ForEach(o.failed.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("\(k): \(v)").font(.caption).foregroundStyle(.red) }
                if !o.skipped.isEmpty { Text("Skipped (already there): \(o.skipped.joined(separator: ", "))").font(.caption) }
                ForEach(o.renamed.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("Kept both: \(k) as \(v)").font(.caption) }
            }
            if let p = problem { Text(p).foregroundStyle(.red) }
            HStack {
                if let o = outcome { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([o.destination]) } }
                Spacer()
                Button(outcome == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(running)
                if outcome == nil {
                    Button("Restore") { restore() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(running || destination == nil || (!whole && chosen.isEmpty))
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Choose"
        p.message = "Choose where to restore to."
        if p.runModal() == .OK { destination = p.url }
    }

    /// The owner's answer to a conflict, asked on the main thread while the
    /// restore waits; "do the same for the rest" remembered.
    final class Asker: @unchecked Sendable {
        var always: Restorer.Conflict?
        func ask(_ path: String) -> Restorer.Conflict {
            if let always { return always }
            return DispatchQueue.main.sync {
                let a = NSAlert()
                a.messageText = "\u{201C}\((path as NSString).lastPathComponent)\u{201D} is already there."
                a.informativeText = "Keep Both saves the backup's copy under the next free name. Replace puts it in place of what's there."
                a.addButton(withTitle: "Keep Both")
                a.addButton(withTitle: "Replace")
                a.addButton(withTitle: "Skip")
                a.buttons[1].hasDestructiveAction = true
                a.showsSuppressionButton = true
                a.suppressionButton?.title = "Do the same for the rest"
                let r = a.runModal()
                let answer: Restorer.Conflict = r == .alertFirstButtonReturn ? .keepBoth : r == .alertSecondButtonReturn ? .replace : .skip
                if a.suppressionButton?.state == .on { always = answer }
                return answer
            }
        }
    }

    func restore() {
        guard let destination else { return }
        running = true
        problem = nil
        let url = model.folderURL(summary)
        let paths = whole ? nil : Array(chosen)
        let asker = Asker()
        Task {
            let result = await Task.detached { () -> Result<Restorer.Outcome, Error> in
                Result {
                    let r = try Restorer(snapshot: url)
                    let into = paths == nil ? try r.newFolder(in: destination) : destination
                    return try r.restore(paths, into: into, conflict: { asker.ask($0) }, onFile: { f in
                        Task { @MainActor in current = f }
                    })
                }
            }.value
            running = false
            switch result {
            case .success(let o): outcome = o
            case .failure(let e): problem = (e as? BackupError)?.message ?? e.localizedDescription
            }
        }
    }
}

/// Settings (W11): the backup folder; thinning (W14).
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Backups") {
                LabeledContent("Backup folder") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.repository.root.lastPathComponent).font(.headline)
                        Text(model.repository.root.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                HStack {
                    Spacer()
                    if model.prefs.repositoryPath != nil { Button("Use Default") { model.useDefaultBackupFolder() } }
                    Button("Choose…") { model.chooseBackupFolder() }
                }
            }
            Section("Older snapshots") {
                Toggle(isOn: $model.prefs.thinning) {
                    Text("Thin older snapshots after each backup")
                    Text("Keeps a card's newest snapshot of each day for a week, of each week for a month, and of each month for a year; always at least two, and any marked Keep. Those removed go to the Trash.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}

/// Registering a new card (C3): a friendly name for it.
struct RegisterSheet: View {
    @Bindable var model: AppModel
    @State private var name = "Mac Plus BlueSCSI"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Register this card?").font(.title3.bold())
            Text("\(model.registering?.name ?? "This card") looks like a BlueSCSI card. Give it a name, and its backups are kept together under it, and it's recognised whenever it's inserted.")
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Text("Nothing is written to the card: the register is kept in the backup folder.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now") { model.notNow() }.keyboardShortcut(.cancelAction)
                Button("Register") { model.registerCard(name) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Restore to a New Card (B13): how to format it, which inserted card,
/// a clear confirmation, then the restore, every file checked; then the
/// replacement, and Eject.
struct NewCardSheet: View {
    @Bindable var model: AppModel
    let summary: Catalog.Summary
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: URL?
    @State private var includeFirmware = false
    @State private var confirming = false
    @State private var running = false
    @State private var current: String?
    @State private var outcome: NewCard.Outcome?
    @State private var problem: String?
    @State private var replaced: Card?

    var manifest: Manifest? { try? Manifest.read(model.folderURL(summary).appendingPathComponent(Manifest.fileName)) }
    var disk: VolumeInfo? { model.disks.first { $0.url == chosen } }
    /// The snapshot's card: its own record, or the registered card with its
    /// volume's UUID (a snapshot made before registering).
    var cardID: UUID? {
        summary.cardID ?? model.register.cards.first { $0.volumeUUID != nil && $0.volumeUUID == summary.volumeUUID }?.id
    }

    func verdict(_ v: VolumeInfo) -> String? {
        guard let m = manifest else { return "The snapshot can't be read." }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: v.url.path)) ?? []
        let free = (try? v.url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
        return NewCard.check(m, cardItems: items, filesystem: v.filesystem, available: free, includeFirmware: includeFirmware)?.message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore \(summary.name) to a New Card").font(.title3.bold())
            Text("Everything the snapshot holds goes onto a new, empty card, ready for the BlueSCSI: every disk image and its configuration, each checked as it's written. Nothing on another card is touched.")
            GroupBox("First, format the new card") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In Disk Utility, select the card, click Erase, and choose Format: ExFAT, Scheme: Master Boot Record. (BlueSCSI recommends the SD Card Formatter's full overwrite format for a new card.) The app never formats a card itself.")
                        .font(.callout)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Inserted cards").font(.headline)
            if model.disks.isEmpty {
                Text("Insert the new card.").foregroundStyle(.secondary)
            }
            ForEach(model.disks, id: \.url) { v in
                let why = verdict(v)
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: chosen == v.url ? "largecircle.fill.circle" : "circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(v.name ?? v.url.lastPathComponent)  \(v.filesystem ?? "")  \(bytes(v.capacity))")
                        Text(why ?? "Empty, and ready.").font(.caption).foregroundStyle(why == nil ? .green : .secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if why == nil && !running { chosen = v.url } }
                .opacity(why == nil ? 1 : 0.6)
            }
            Toggle("Include BlueSCSI firmware update packages", isOn: $includeFirmware)
                .help("Left out normally: a firmware package on the card makes the BlueSCSI reflash itself when it starts.")
            if running { HStack { ProgressView().controlSize(.small); Text(current ?? "").font(.caption).lineLimit(1) } }
            if let o = outcome {
                Label(o.succeeded ? "Restored \(o.written.count) files; all \(o.checked) checked on the card." : "Some files don't match: \(o.failed.keys.sorted().joined(separator: ", "))",
                      systemImage: o.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(o.succeeded ? .green : .red)
                if o.succeeded, let v = disk {
                    if let r = replaced { Text("Recorded as \(r.name)'s replacement: its backups carry on under that name.").font(.callout) }
                    else if let id = cardID {
                        Button("Use as \(model.cardName(of: summary))'s Replacement") { replaced = model.makeReplacement(for: id, with: v) }
                    }
                    Text("Eject the card, put it in the BlueSCSI, and switch the Plus on.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let p = problem { Text(p).foregroundStyle(.red) }
            HStack {
                if outcome?.succeeded == true, let v = disk { Button("Eject") { model.eject(v.url) } }
                Spacer()
                Button(outcome == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(running)
                if outcome == nil {
                    Button("Restore to Card…") { confirming = true }
                        .keyboardShortcut(.defaultAction)
                        .disabled(running || disk == nil || (disk.map(verdict) ?? "x") != nil)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .alert("Restore onto \(disk?.name ?? "this card")?", isPresented: $confirming) {
            Button("Restore to Card") { restore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(summary.name), \(bytes(summary.bytes)), is written to \(disk?.name ?? "the card") (\(disk?.filesystem ?? ""), \(bytes(disk?.capacity))). The Macintosh Plus will use these disks when the card goes in its BlueSCSI. This isn't a copy of the whole old card, only of its files.")
        }
    }

    func restore() {
        guard let card = chosen else { return }
        running = true
        problem = nil
        let snap = model.folderURL(summary), firmware = includeFirmware
        Task {
            let result = await Task.detached { () -> Result<NewCard.Outcome, Error> in
                Result { try NewCard.restore(snap, onto: card, includeFirmware: firmware) { f in
                    Task { @MainActor in current = f }
                } }
            }.value
            running = false
            switch result {
            case .success(let o): outcome = o
            case .failure(let e as NewCard.Problem): problem = e.message
            case .failure(let e): problem = (e as? BackupError)?.message ?? e.localizedDescription
            }
        }
    }
}
