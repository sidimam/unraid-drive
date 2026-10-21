import SwiftUI
import UnraidGatewayKit
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// Settings › Profiles › server › **Sync**: the folder syncs and backups this installation runs
/// against that server (1.5). Each row: kind, local label → Unraid path, state, a switch, Run now.
struct SyncSettingsView: View {
    @EnvironmentObject private var model: ServersModel
    @ObservedObject private var sync = SyncCoordinator.shared
    let server: ServerConfig
    @State private var editing: SyncPair?
    @State private var adding = false
    @State private var files: SyncPair?

    var body: some View {
        List {
            Section {
                ForEach(sync.pairs(for: server)) { p in
                    SyncPairRow(pair: p, progress: sync.progress[p.id])
                        .contentShape(Rectangle())
                        .onTapGesture { files = p }
                        .contextMenu {
                            Button { Task { await sync.run(p, trigger: "manual") } } label: { Label("Run now", systemImage: "play") }.disabled(sync.isRunning(p.id))
                            Button { files = p } label: { Label("Recent files", systemImage: "list.bullet.rectangle") }
                            Button { editing = p } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { Task { await sync.remove(p) } } label: { Label("Remove sync", systemImage: "trash") }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await sync.remove(p) } } label: { Label("Remove", systemImage: "trash") }
                            Button { editing = p } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                        }
                }
                Button { adding = true } label: { Label("Add a sync", systemImage: "plus.circle") }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Sync")
        .sheet(isPresented: $adding) { NavigationStack { SyncPairEditorView(server: server, pair: nil) }.sheetFrame() }
        .sheet(item: $editing) { p in NavigationStack { SyncPairEditorView(server: server, pair: p) }.sheetFrame() }
        .sheet(item: $files) { p in NavigationStack { SyncFilesView(pair: p) }.sheetFrame() }
        .task { await sync.refreshFromGateway(server) }
    }

    private var footer: LocalizedStringKey {
        #if os(macOS)
        return "A sync keeps a folder of this Mac and a folder of Unraid aligned through the gateway, or backs the Photos library up. Pairs run in the background; the menu bar panel shows progress and problems. Pausing a pair here or in the gateway's web UI stops it until resumed."
        #else
        return "Back the Photos library up to Unraid, or send the Downloads folder of this device. Runs happen while the app is open and, when the system allows it, in the background on Wi-Fi and power. Pausing a pair here or in the gateway's web UI stops it until resumed."
        #endif
    }
}

struct SyncPairRow: View {
    @ObservedObject private var sync = SyncCoordinator.shared
    let pair: SyncPair
    let progress: SyncEngine.Progress?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pair.symbol).imageScale(.large).foregroundStyle(.tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(pair.localLabel) \(arrow) \(pair.remotePath)").font(.body).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                if let progress, progress.phase != "done" {
                    if progress.total > 0 { ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) }
                    else { ProgressView() }
                    Text(progress.current.map { "\(progress.phase == "scanning" ? String(localized: "Scanning…") : String(localized: "Syncing")) · \($0)" } ?? (progress.phase == "scanning" ? String(localized: "Scanning…") : String(localized: "Syncing…")))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    HStack(spacing: 6) { stateDot; Text(stateText).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Toggle("", isOn: Binding(get: { pair.enabled }, set: { v in Task { await sync.setEnabled(pair, v) } })).labelsHidden()
                    .disabled(pair.pausedByGateway != nil)
                Button { Task { await sync.run(pair, trigger: "manual") } } label: { Image(systemName: "play.circle") }.buttonStyle(.plain)
                    .disabled(sync.isRunning(pair.id) || pair.pausedByGateway != nil)
                    .help(Text("Run now"))
            }
        }
        .padding(.vertical, 2)
    }

    private var arrow: String { pair.mode == .down ? "←" : (pair.mode == .both ? "⇄" : "→") }
    private var subtitle: String {
        var parts: [String] = [kindTitle(pair.kind), modeTitle(pair.mode)]
        parts.append(scheduleTitle(pair.schedule))
        if pair.wifiOnly { parts.append(String(localized: "Wi-Fi only")) }
        return parts.joined(separator: " · ")
    }
    private var stateDot: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        if pair.pausedByGateway != nil { return .orange }
        if !pair.enabled { return .gray }
        guard let r = pair.lastRun else { return .gray }
        switch r.status { case .ok: return .green; case .partial: return .orange; case .failed: return .red; case .skipped: return .gray }
    }
    private var stateText: String {
        if let by = pair.pausedByGateway { return String(localized: "Paused on the gateway (\(by)) — resume it in the web UI") }
        if !pair.enabled { return String(localized: "Paused") }
        guard let r = pair.lastRun else { return String(localized: "Never run yet") }
        let when = r.at.formatted(.relative(presentation: .named))
        switch r.status {
        case .ok: return String(localized: "Last run \(when): \(r.files) files, \(ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file))")
        case .partial: return String(localized: "Last run \(when) with problems: \(r.conflicts) conflicts, \(r.errors) errors") + (r.error.map { " · " + $0 } ?? "")
        case .failed: return String(localized: "Last run \(when) failed") + (r.error.map { ": " + $0 } ?? "")
        case .skipped: return String(localized: "Last run \(when) skipped")
        }
    }
}

func kindTitle(_ k: SyncKind) -> String {
    switch k {
    case .folder: return String(localized: "Folder sync")
    case .photos: return String(localized: "Photos backup")
    case .downloads: return String(localized: "Downloads")
    }
}
func modeTitle(_ m: SyncMode) -> String {
    switch m {
    case .up: return String(localized: "\(SyncCoordinator.deviceTag) → Unraid")
    case .down: return String(localized: "Unraid → \(SyncCoordinator.deviceTag)")
    case .both: return String(localized: "Two-way")
    }
}
func scheduleTitle(_ s: SyncSchedule) -> String {
    switch s {
    case .continuous: return String(localized: "Continuous")
    case .hourly: return String(localized: "Every hour")
    case .daily: return String(localized: "Every day")
    case .manual: return String(localized: "Manual")
    }
}

/// Add / edit one pair.
struct SyncPairEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let pair: SyncPair?
    @State private var kind: SyncKind
    @State private var localLabel: String
    @State private var bookmark: Data?
    @State private var remotePath: String
    @State private var mode: SyncMode
    @State private var conflicts: ConflictPolicy
    @State private var deletions: DeletionPolicy
    @State private var schedule: SyncSchedule
    @State private var excludes: String
    @State private var wifiOnly: Bool
    @State private var pickingRemote = false
    @State private var pickingLocal = false
    @State private var error: String?
    @State private var saving = false

    init(server: ServerConfig, pair: SyncPair?) {
        self.server = server; self.pair = pair
        #if os(macOS)
        let defaultKind: SyncKind = .folder
        #else
        let defaultKind: SyncKind = .photos
        #endif
        _kind = State(initialValue: pair?.kind ?? defaultKind)
        _localLabel = State(initialValue: pair?.localLabel ?? "")
        _bookmark = State(initialValue: pair?.localBookmark)
        _remotePath = State(initialValue: pair?.remotePath ?? "")
        _mode = State(initialValue: pair?.mode ?? .up)
        _conflicts = State(initialValue: pair?.conflicts ?? .newest)
        _deletions = State(initialValue: pair?.deletions ?? .keep)
        _schedule = State(initialValue: pair?.schedule ?? .continuous)
        _excludes = State(initialValue: (pair?.excludes ?? []).joined(separator: ", "))
        _wifiOnly = State(initialValue: pair?.wifiOnly ?? false)
    }

    private var availableKinds: [SyncKind] {
        #if os(macOS)
        return [.folder, .photos]
        #else
        return [.photos, .downloads]
        #endif
    }

    var body: some View {
        Form {
            Section {
                Picker("What to sync", selection: $kind) {
                    ForEach(availableKinds, id: \.self) { k in Label(kindTitle(k), systemImage: SyncPair(serverID: "", kind: k, localLabel: "", remotePath: "").symbol).tag(k) }
                }
                .onChange(of: kind) { _, k in if k == .photos { localLabel = String(localized: "Photos library"); mode = .up; bookmark = nil } else if k == .downloads { mode = .up } }
                if kind != .photos {
                    LabeledContent {
                        Button(localLabel.isEmpty ? String(localized: "Choose…") : localLabel) { pickLocal() }
                    } label: { Label(kind == .downloads ? "Downloads folder" : "Folder on this \(SyncCoordinator.deviceTag)", systemImage: "folder") }
                }
                LabeledContent {
                    Button(remotePath.isEmpty ? String(localized: "Choose…") : remotePath) { pickingRemote = true }
                } label: { Label("Folder on Unraid", systemImage: "externaldrive") }
            } footer: {
                if kind == .photos { Text("Originals of photos and videos (RAW, HEIC, both halves of a Live Photo) are copied into year/month folders under the Unraid folder, with an albums.json listing your albums. Nothing is ever deleted on Unraid.") }
                else if kind == .downloads { Text("Files that appear in the chosen folder are sent to Unraid. Pick the Downloads folder of this device (or any folder you like).") }
            }
            if kind == .folder {
                Section {
                    Picker("Direction", selection: $mode) {
                        ForEach(SyncMode.allCases, id: \.self) { m in Text(modeTitle(m)).tag(m) }
                    }
                    Picker("When a file changed on both sides", selection: $conflicts) {
                        Text("Newest wins").tag(ConflictPolicy.newest)
                        Text("Keep both (rename)").tag(ConflictPolicy.keepBoth)
                        Text("Keep the existing copy").tag(ConflictPolicy.keepExisting)
                        Text("Ask me").tag(ConflictPolicy.ask)
                    }
                    Picker("Deleted files", selection: $deletions) {
                        Text("Keep them on the other side").tag(DeletionPolicy.keep)
                        Text("Delete on the other side too").tag(DeletionPolicy.mirror)
                    }
                    TextField("Exclude (patterns, comma separated)", text: $excludes)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                } footer: { Text("Example: *.tmp, node_modules, Thumbs.db. .DS_Store and partial downloads are always excluded.") }
            }
            Section {
                Picker("Runs", selection: $schedule) {
                    ForEach(SyncSchedule.allCases, id: \.self) { s in Text(scheduleTitle(s)).tag(s) }
                }
                #if !os(macOS)
                Toggle("Only on Wi-Fi", isOn: $wifiOnly)
                #endif
            } footer: {
                #if os(macOS)
                Text("Continuous: the folder is watched and the pair also runs every 15 minutes; otherwise at the chosen interval or only when you press Run now.")
                #else
                Text("Runs happen while the app is open and, when the system allows it, in the background on power and Wi-Fi.")
                #endif
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
        }
        .formStyle(.grouped)
        .navigationTitle(pair == nil ? "Add a sync" : "Edit sync")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(!valid || saving) }
        }
        .sheet(isPresented: $pickingRemote) {
            NavigationStack {
                FolderPickerView(server: server, title: "Folder on Unraid", excluding: [], path: "/", copy: false, onChoose: { p in remotePath = p; pickingRemote = false }, onCancel: { pickingRemote = false })
            }.sheetFrame()
        }
        #if !os(macOS)
        .sheet(isPresented: $pickingLocal) { FolderDocumentPicker { url in storeBookmark(url) } }
        #endif
    }

    private var valid: Bool { !remotePath.isEmpty && remotePath != "/" && (kind == .photos || bookmark != nil) }

    private func pickLocal() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        if kind == .downloads { panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
        if panel.runModal() == .OK, let url = panel.url { storeBookmark(url) }
        #else
        pickingLocal = true
        #endif
    }

    private func storeBookmark(_ url: URL) {
        do {
            bookmark = try SyncPair.bookmark(for: url)
            let home = NSHomeDirectory()
            var label = url.path
            if label.hasPrefix(home) { label = "~" + label.dropFirst(home.count) }
            if label.contains("/Library/Mobile Documents/com~apple~CloudDocs") { label = "iCloud Drive" + label.components(separatedBy: "com~apple~CloudDocs").last! }
            localLabel = kind == .downloads && url.lastPathComponent == "Downloads" ? String(localized: "Downloads") : label
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        saving = true; defer { saving = false }
        var p = pair ?? SyncPair(serverID: server.id, kind: kind, localLabel: localLabel, remotePath: remotePath)
        p.kind = kind; p.localLabel = kind == .photos ? String(localized: "Photos library") : localLabel; p.localBookmark = kind == .photos ? nil : bookmark
        p.remotePath = GatewayPath.clean(remotePath); p.mode = kind == .folder ? mode : .up
        p.conflicts = conflicts; p.deletions = deletions; p.schedule = schedule; p.wifiOnly = wifiOnly
        p.excludes = excludes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if kind == .photos, !(await PhotosBackup.authorize()) {
            error = String(localized: "Photos access is not allowed: enable it in Settings › Privacy › Photos."); return
        }
        await SyncCoordinator.shared.save(p)
        dismiss()
        if pair == nil { Task { await SyncCoordinator.shared.run(p, trigger: "manual") } }
    }
}

#if !os(macOS)
/// Folder picker for the Downloads sync (security-scoped access to the chosen folder).
struct FolderDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        c.allowsMultipleSelection = false; c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let u = urls.first else { return }
            _ = u.startAccessingSecurityScopedResource()
            onPick(u)
        }
    }
}
#endif

/// Recent files of one pair (what moved, conflicts, failures), newest first.
struct SyncFilesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sync = SyncCoordinator.shared
    let pair: SyncPair

    var body: some View {
        List {
            if let r = pair.lastRun {
                Section {
                    LabeledContent("Last run", value: r.at.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Result", value: r.status.rawValue.capitalized)
                    LabeledContent("Files", value: "\(r.files) · \(ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file))")
                    if r.conflicts > 0 { LabeledContent("Conflicts", value: "\(r.conflicts)") }
                    if r.errors > 0 { LabeledContent("Errors", value: "\(r.errors)") }
                    if let e = r.error { Text(e).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section("Recent files") {
                let files = sync.lastFiles[pair.id] ?? []
                if files.isEmpty { Text("No file moved yet.").foregroundStyle(.secondary) }
                ForEach(files) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(f)).foregroundStyle(f.outcome == .failed ? .red : (f.outcome == .conflict ? .orange : .secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text((f.path as NSString).lastPathComponent).font(.body)
                            Text("\(f.time.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file))\(f.detail.map { " · " + $0 } ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(pair.localLabel)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func icon(_ f: SyncFileRecord) -> String {
        switch f.direction { case .up: return "arrow.up.circle"; case .down: return "arrow.down.circle"; case .delete: return "trash"; case .conflict: return "exclamationmark.triangle" }
    }
}
