import SwiftUI
import MacintoshBackupKit

/// The window (W1): the status at the top; the card on the left; the
/// history on the right, the selected snapshot's manifest below it.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var restoring: Catalog.Summary?
    @State private var toNewCard: Catalog.Summary?
    @State private var deleting: Catalog.Summary?
    @State private var clearing = false

    var body: some View {
        VStack(spacing: 0) {
            StatusView(model: model)
            Divider()
            HSplitView {
                SourceView(model: model)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                HistoryView(model: model, restoring: $restoring, toNewCard: $toNewCard, deleting: $deleting, clearing: $clearing)
                    .frame(minWidth: 520)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { toolbar }
        .sheet(isPresented: Binding(get: { model.state == .confirming }, set: { if !$0 && model.state == .confirming { model.cancelConfirmation() } })) {
            BackupSheet(model: model)
        }
        .sheet(item: $restoring) { s in RestoreSheet(model: model, summary: s) }
        .sheet(item: $toNewCard) { s in NewCardSheet(model: model, summary: s) }
        .sheet(isPresented: Binding(get: { model.registering != nil && model.state != .confirming },
                                    set: { if !$0 { model.notNow() } })) {
            RegisterSheet(model: model)
        }
        .alert("Is this \(model.asking?.1.name ?? "your card")?", isPresented: Binding(get: { model.asking != nil }, set: { _ in })) {
            Button("Yes, the Same Card") { model.answerProbable(same: true) }
            Button("No, a Different Card") { model.answerProbable(same: false) }
        } message: {
            Text("It has the same name, size and format as \(model.asking?.1.name ?? "a card you've registered"), but macOS gives it a different identity, as it does a card that's been reformatted. Its backups will be kept together with that card's if it's the same one.")
        }
        .alert(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Move to Trash", role: .destructive) { if let s = deleting { model.delete(s) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleteMessage)
        }
        .alert("Clear the incomplete jobs?", isPresented: $clearing) {
            Button("Move to Trash", role: .destructive) { model.clearIncomplete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They hold no restore points: backups that failed, were cancelled, or found the card changed. Your snapshots aren't affected.")
        }
    }

    var deleteTitle: String { "Delete the snapshot \(deleting?.name ?? "")?" }
    var deleteMessage: String {
        guard let s = deleting else { return "" }
        let last = model.isLast(s) ? "It's the only backup of this card: once it's gone, there's nothing to restore it from. " : ""
        return last + "It goes to the Trash, so it can be put back until the Trash is emptied."
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.askToBackUp() } label: { Label("Back Up Now", systemImage: "externaldrive.badge.timemachine") }
                .disabled(!(model.state == .ready || model.isFinished) || model.running)
                .help("Back up the chosen card")
            Button { if let s = model.summary(model.selection) { model.reveal(s) } } label: { Label("Browse Backups", systemImage: "folder") }
                .disabled(model.summary(model.selection)?.isRestorePoint != true)
                .help("Show the selected snapshot's files in the Finder")
            Button { model.verifySelected() } label: { Label("Verify Backup", systemImage: "checkmark.seal") }
                .disabled(model.summary(model.selection)?.isRestorePoint != true || model.running)
                .help("Check the selected snapshot against its manifest")
            Button { restoring = model.summary(model.selection) } label: { Label("Restore…", systemImage: "arrow.uturn.backward") }
                .disabled(model.summary(model.selection)?.isRestorePoint != true || model.running)
                .help("Restore files from the selected snapshot")
            Button { model.openBackupFolder() } label: { Label("Open Backup Folder", systemImage: "folder.badge.gearshape") }
                .help("Open the backup folder in the Finder")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .help("Settings")
        }
    }
}

// MARK: The status (W1, W4, W5, W6)

struct StatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol).foregroundStyle(tint).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.canEject {
                    Button { model.eject() } label: { Label("Eject", systemImage: "eject") }
                        .help("Eject the card, ready to go back in the BlueSCSI")
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last backup: " + when(model.catalog?.lastBackup?.started)).font(.callout)
                    if let r = model.lastResult { Text("Latest: \(r.manifest.status.rawValue)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if model.state == .backingUp, let p = model.progress {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progressText(p)).font(.callout).lineLimit(1).truncationMode(.middle)
                        if p.bytesTotal > 0 { ProgressView(value: Double(p.bytesDone), total: Double(p.bytesTotal)) }
                        else { ProgressView().progressViewStyle(.linear) }
                    }
                    Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
                }
            }
            if model.state == .waiting {
                Label("Before you take the card out, shut the Macintosh Plus down with Shut Down in the Special menu, and switch it off when it says you may. Losing power while the Plus is using the card can damage its disks.",
                      systemImage: "power").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    var symbol: String {
        switch model.state {
        case .finished(.verified): model.lastResult?.manifest.warnings.isEmpty == false ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .finished, .failed: "xmark.octagon.fill"
        case .backingUp, .scanning: "arrow.triangle.2.circlepath"
        default: "sdcard"
        }
    }
    var tint: Color {
        switch model.state {
        case .finished(.verified): model.lastResult?.manifest.warnings.isEmpty == false ? .orange : .green
        case .finished, .failed: .red
        default: .secondary
        }
    }

    var headline: String {
        switch model.state {
        case .waiting: "Waiting for a card"
        case .scanning: "Looking at \(model.source?.volumeName ?? "the card")…"
        case .ready, .confirming: model.volume != nil ? "\(name) is connected" : "\(name) is ready to back up"
        case .backingUp: "Backing up \(name)…"
        case .finished(.verified): model.lastResult?.manifest.warnings.isEmpty == false ? "Backed up and verified, with warnings" : "Backed up and verified"
        case .finished(.inconsistent): "Not verified: the card changed during the backup"
        case .finished(.failed): "The backup failed"
        case .finished(.cancelled): model.cardRemoved ? "The card was removed during the backup" : "The backup was cancelled"
        case .failed: "The backup couldn't start"
        }
    }

    var detail: String {
        switch model.state {
        case .waiting: return "Insert the BlueSCSI card: it's recognised when it appears. (Or click Choose Card.)"
        case .scanning, .backingUp: return "Nothing is written to the card."
        case .ready, .confirming:
            return "\(model.inventory?.files.count ?? 0) files, \(bytes(model.inventory?.totalBytes)). Nothing is copied until you click Back Up Now."
        case .finished(let s):
            guard let r = model.lastResult else { return "" }
            if s == .verified {
                let removed = r.removed.isEmpty ? ""
                    : " Removed \(r.removed.count) older snapshot\(r.removed.count == 1 ? "" : "s"): \(r.removed.joined(separator: ", "))."
                return "\(r.manifest.name): \(r.manifest.totals.files) files, every one checked.\(removed) Eject the card in the Finder before you put it back in the BlueSCSI, and put it back before you switch the Plus on."
            }
            let bad = r.manifest.entries.filter { $0.result == .failed || $0.result == .changed }
                .prefix(3).map { "\($0.path): \($0.note ?? $0.result!.rawValue)" }
            return (bad.isEmpty ? "" : bad.joined(separator: " ") + " ") + "It isn't a restore point; your earlier backups aren't affected."
        case .failed(let why): return why
        }
    }

    var name: String { model.cardName }

    func progressText(_ p: BackupProgress) -> String {
        switch p.stage {
        case .scanning: "Looking at the card…"
        case .copying: "Copying \(p.filesDone + 1 > p.filesTotal ? p.filesTotal : p.filesDone + 1) of \(p.filesTotal) (\(bytes(p.bytesDone)) of \(bytes(p.bytesTotal))): \(p.current ?? "")"
        case .checking: "Checking the card hasn't changed…"
        case .finishing: "Finishing…"
        }
    }
}

// MARK: The card (W1, W3, W13)

struct SourceView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Card") {
                if let s = model.source {
                    if let c = model.card { LabeledContent("Registered as", value: c.name) }
                    else if model.volume != nil {
                        LabeledContent("Registered as") {
                            Button("Register…") { model.registering = model.volume }
                        }
                    }
                    LabeledContent("Name", value: s.volumeName ?? s.url.lastPathComponent)
                    LabeledContent("Location") { Text(s.url.path).lineLimit(1).truncationMode(.middle) }
                    LabeledContent("Format", value: s.filesystem ?? "—")
                    LabeledContent("Used", value: "\(bytes(s.used)) of \(bytes(s.capacity))")
                    if let e = model.evidence {
                        LabeledContent("BlueSCSI", value: e == .strong ? "its configuration or log is here" : e == .likely ? "its disk images are here" : "no sign of it")
                    }
                } else {
                    Text("No card chosen.").foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.source == nil ? "Choose Card…" : "Choose Another…") { model.chooseCard() }
                        .disabled(model.running)
                    if model.source != nil { Button("Forget") { model.forgetCard() }.disabled(model.running) }
                }
            }
            if let inv = model.inventory {
                Section("Contents") {
                    LabeledContent("Files", value: "\(inv.files.count), \(bytes(inv.totalBytes))")
                    ForEach(model.images, id: \.path) { e in
                        LabeledContent {
                            Text(bytes(e.size))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: e.cleanShutdown == false ? "exclamationmark.triangle.fill" : "internaldrive")
                                    .foregroundStyle(e.cleanShutdown == false ? .orange : .secondary)
                                Text(e.path).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    ForEach(model.configuration, id: \.path) { e in
                        LabeledContent { Text(bytes(e.size)) } label: { Label(e.path, systemImage: "doc.text").lineLimit(1) }
                    }
                }
                if !model.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(model.warnings, id: \.self) { w in
                            Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        }
                    }
                }
            } else if let p = model.scanProblem {
                Section { Label(p, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: The history (W1, W8, W9, W10)

struct HistoryView: View {
    @Bindable var model: AppModel
    @Binding var restoring: Catalog.Summary?
    @Binding var toNewCard: Catalog.Summary?
    @Binding var deleting: Catalog.Summary?
    @Binding var clearing: Bool

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                Table(model.restorePoints, selection: Binding(get: { model.selection }, set: { model.select($0) })) {
                    TableColumn("Date") { s in
                        HStack(spacing: 4) {
                            if let id = s.snapshotID, model.pins.contains(id) { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                            Text(when(s.started))
                        }
                    }.width(min: 140, ideal: 160)
                    TableColumn("Card") { s in Text(model.cardName(of: s)) }.width(min: 80, ideal: 110)
                    TableColumn("Files") { s in Text("\(s.files)") }.width(50)
                    TableColumn("Size") { s in Text(bytes(s.bytes)) }.width(min: 60, ideal: 70)
                    TableColumn("On disk") { s in Text(bytes(s.storedBytes)) }.width(min: 60, ideal: 70)
                    TableColumn("Status") { s in
                        if s.unclean { Label("Verified", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("A disk in it wasn't shut down cleanly") }
                        else if s.warnings > 0 { Label("Verified", systemImage: "exclamationmark.triangle").help("\(s.warnings) warning(s)") }
                        else { Label("Verified", systemImage: "checkmark.seal") }
                    }.width(min: 80, ideal: 90)
                    TableColumn("Name") { s in Text(s.name).foregroundStyle(.secondary) }
                }
                .contextMenu(forSelectionType: String.self) { items in
                    if let folder = items.first, let s = model.summary(folder) {
                        Button("Restore…") { restoring = s }
                        Button("Restore to a New Card…") { toNewCard = s }
                        Button("Verify Backup") { model.select(folder); model.verifySelected() }
                        Button("Show in Finder") { model.reveal(s) }
                        Button(s.snapshotID.map { model.pins.contains($0) } == true ? "Don't Keep" : "Keep (Never Thin)") { model.togglePin(s) }
                        Divider()
                        Button("Delete…", role: .destructive) { deleting = s }
                    }
                }
                HStack {
                    Text("\(model.restorePoints.count) snapshot\(model.restorePoints.count == 1 ? "" : "s"), \(bytes(model.restorePoints.reduce(0) { $0 + $1.storedBytes })) on disk")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !model.incomplete.isEmpty {
                        Text("\(model.incomplete.count) incomplete job\(model.incomplete.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.orange)
                        Button("Clear…") { clearing = true }.controlSize(.small).disabled(model.running)
                    }
                    if let p = model.catalogProblem { Text(p).font(.caption).foregroundStyle(.red) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .frame(minHeight: 180)
            DetailView(model: model).frame(minHeight: 160)
        }
    }
}

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let m = model.selectedManifest {
                HStack {
                    Text(m.name).font(.headline)
                    Spacer()
                    if model.verifying { ProgressView().controlSize(.small); Text(model.verifyingFile ?? "").font(.caption).lineLimit(1) }
                    else if let v = model.verification {
                        Label(v.passed ? "Verified: \(v.filesChecked) files match" : "\(v.problems.count) problem\(v.problems.count == 1 ? "" : "s") found",
                              systemImage: v.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                            .foregroundStyle(v.passed ? .green : .red)
                    }
                }
                if let v = model.verification, !v.passed {
                    ForEach(v.problems, id: \.path) { p in
                        Text("\(p.path): \(describe(p.kind))").font(.caption).foregroundStyle(.red)
                    }
                }
                ForEach(m.warnings, id: \.self) { w in Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Table(m.entries) {
                    TableColumn("Path") { e in Text(e.path).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Kind") { e in Text(e.category.label) }.width(min: 90, ideal: 110)
                    TableColumn("Size") { e in Text(e.kind == .file ? bytes(e.size) : "") }.width(70)
                    TableColumn("Result") { e in Text(e.result?.rawValue ?? "") }.width(70)
                }
            } else {
                Text("Select a snapshot to see what it holds.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
    }

    func describe(_ k: Verification.Problem.Kind) -> String {
        switch k {
        case .missing: "missing"
        case .wrongSize: "the wrong size"
        case .wrongChecksum: "its contents have changed"
        case .unreadable: "can't be read"
        case .unexpected: "not in the manifest"
        }
    }
}


extension MacintoshBackupKit.Category {
    var label: String {
        switch self {
        case .diskImage: "Disk image"
        case .configuration: "Configuration"
        case .log: "Log"
        case .firmware: "Firmware"
        case .macOSMetadata: "macOS file"
        case .other: "Other"
        }
    }
}
