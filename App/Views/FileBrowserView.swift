import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UnraidGatewayKit

/// The in-app file explorer, in the spirit of the Files app: list or icons, sorting, search, Quick
/// Look, viewers for what Quick Look cannot show (MKV/AVI… through mpv, EPUB, comics, archives), and
/// the usual file operations (new folder, upload, rename, move, copy, share, delete) — all through
/// the gateway with the user's Unraid permissions. Day-to-day work can still happen in the Files
/// app / Finder location; this is the same tree without leaving the app.
struct FileBrowserView: View {
    @EnvironmentObject private var model: ServersModel
    @ObservedObject private var clipboard = ExplorerClipboard.shared
    let server: ServerConfig
    let path: String
    @State private var entries: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var search = ""
    @AppStorage("explorer.sort") private var sortKey = "name"
    @AppStorage("explorer.grid") private var grid = false
    @State private var busy: String?
    // Selection (Select mode): several files/folders at once, acted on together.
    @State private var selecting = false
    @State private var selection = Set<String>()
    #if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
    #endif
    // Presentation
    @State private var preview: URL?
    @State private var viewer: FSEntry?
    @State private var info: FSEntry?
    @State private var newFolder = false
    @State private var newFolderName = ""
    @State private var renaming: FSEntry?
    @State private var renameName = ""
    @State private var moving: (entries: [FSEntry], copy: Bool)?
    @State private var deleting: [FSEntry]?
    @State private var importing = false
    @State private var shareURLs: [URL]?
    @State private var exportURLs: [URL] = []
    @State private var exporting = false
    @State private var opError: String?

    private var readOnly: Bool {
        guard let share = path.split(separator: "/").first, let c = model.client(for: server) else { return false }
        return c.access(forShare: String(share)) == .readOnly
    }
    private var visible: [FSEntry] {
        let filtered = search.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return filtered.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortKey {
            case "date": return a.mtime > b.mtime
            case "size": return a.size > b.size
            case "kind": return FileKind.of(a).rawValue < FileKind.of(b).rawValue
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
    /// The selected entries, in display order (only what is really in this folder).
    private var selected: [FSEntry] { visible.filter { selection.contains($0.id) } }
    private var canModify: Bool { !readOnly && path != "/" }

    var body: some View {
        Group {
            if grid { gridView } else { listView }
        }
        .overlay {
            if loading && entries.isEmpty { ProgressView() }
            else if let error, entries.isEmpty { ContentUnavailableView("Cannot load this folder", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if !loading && entries.isEmpty { ContentUnavailableView(path == "/" ? "No shares" : "Empty folder", systemImage: "folder") }
        }
        .searchable(text: $search, prompt: Text("Search in this folder"))
        .navigationTitle(selecting ? Text("\(selection.count) selected") : Text(path == "/" ? server.name : GatewayPath.name(path)))
        .inlineNavigationTitle()
        .toolbar { toolbarItems }
        #if os(iOS) || os(visionOS)
        .environment(\.editMode, $editMode)
        #endif
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: selecting) { _, on in
            #if os(iOS) || os(visionOS)
            editMode = on ? .active : .inactive
            #endif
            if !on { selection.removeAll() }
        }
        .quickLookPreview($preview)
        .sheet(item: $viewer) { e in FileViewerSheet(server: server, entry: e).sheetFrame() }
        .sheet(item: $info) { e in NavigationStack { FileInfoView(server: server, entry: e) }.sheetFrame() }
        .sheet(isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })) {
            if let m = moving {
                NavigationStack {
                    FolderPickerView(server: server, title: m.copy ? "Copy to" : "Move to", excluding: Set(m.entries.map(\.path)), copy: m.copy, onChoose: { dest in
                        moving = nil
                        Task { await transfer(m.entries, to: dest, copy: m.copy) }
                    }, onCancel: { moving = nil })
                }.sheetFrame()
            }
        }
        .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
            if let urls = shareURLs { ShareSheet(urls: urls).sheetFrame() }
        }
        .fileMover(isPresented: $exporting, files: exportURLs) { result in
            if case .failure(let e) = result { opError = e.localizedDescription }
            exportURLs = []
        }
        .alert("New folder", isPresented: $newFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameName)
            Button("Rename") { if let r = renaming { Task { await rename(r, to: renameName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) { if let d = deleting { Task { await remove(d) } } } label: {
                if let d = deleting, d.count == 1 { Text("Delete \(d[0].name)") } else { Text("Delete \(deleting?.count ?? 0) items") }
            }
        } message: { Text("The files are removed from the NAS. There is no trash on the gateway.") }
        .alert("Something went wrong", isPresented: Binding(get: { opError != nil }, set: { if !$0 { opError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(opError ?? "") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await upload(urls) } }
        }
        .overlay(alignment: .bottom) {
            if let busy {
                HStack { ProgressView(); Text(busy).font(.callout) }.padding(12).background(.regularMaterial, in: Capsule()).padding().padding(.bottom, selecting ? 64 : 0)
            }
        }
    }

    private var deleteTitle: Text {
        if let d = deleting, d.count > 1 { return Text("Delete \(d.count) items?") }
        return Text("Delete?")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if selecting {
                Button { selection = Set(visible.map(\.id)) } label: { Label("Select all", systemImage: "checklist.checked") }
                    .disabled(selection.count == visible.count)
                Button { selecting = false } label: { Text("Done").bold() }
            } else {
                Menu {
                    Picker("Sort by", selection: $sortKey) {
                        Label("Name", systemImage: "textformat").tag("name")
                        Label("Kind", systemImage: "doc").tag("kind")
                        Label("Date", systemImage: "calendar").tag("date")
                        Label("Size", systemImage: "arrow.up.arrow.down").tag("size")
                    }
                    Divider()
                    Button { grid = false } label: { Label("List", systemImage: grid ? "list.bullet" : "checkmark") }
                    Button { grid = true } label: { Label("Icons", systemImage: grid ? "checkmark" : "square.grid.2x2") }
                    if path != "/" {
                        Divider()
                        Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }.disabled(visible.isEmpty)
                    }
                } label: { Label("View options", systemImage: "arrow.up.arrow.down.circle") }
                if path != "/" {
                    Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }.disabled(visible.isEmpty)
                } else {
                    // Server settings: dashboard, shares to show, connection test, location, credentials.
                    NavigationLink { ServerDetailView(server: server) } label: { Label("Settings", systemImage: "gearshape") }
                }
                if canModify {
                    Menu {
                        Button { newFolderName = ""; newFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                        Button { importing = true } label: { Label("Upload files…", systemImage: "square.and.arrow.up") }
                        if let c = clipboard.pasteable(into: path, server: server) {
                            Divider()
                            Button { Task { await paste(into: path) } } label: { Label(c.cut ? "Paste (move) \(c.label)" : "Paste \(c.label)", systemImage: "doc.on.clipboard") }
                                .keyboardShortcut("v", modifiers: .command)
                        }
                    } label: { Label("Add", systemImage: "plus") }
                }
            }
        }
    }

    /// The bar under the list in Select mode: every action applies to the whole selection.
    private var selectionBar: some View {
        let items = selected
        let none = items.isEmpty
        let filesOnly = items.filter { !$0.isDirectory }
        return HStack(spacing: 4) {
            barButton("Copy", "doc.on.doc", disabled: none || path == "/") { clipboard.copy(items, server: server); selecting = false }
            if canModify {
                barButton("Cut", "scissors", disabled: none) { clipboard.cut(items, server: server); selecting = false }
                barButton("Move…", "folder", disabled: none) { moving = (items, false) }
                barButton("Copy to…", "doc.on.doc.fill", disabled: none) { moving = (items, true) }
            }
            barButton("Download", "arrow.down.circle", disabled: none) { Task { await download(items) } }
            barButton("Share…", "square.and.arrow.up", disabled: filesOnly.isEmpty) { Task { await share(filesOnly) } }
            if canModify {
                barButton("Delete", "trash", disabled: none, role: .destructive) { deleting = items }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func barButton(_ title: LocalizedStringKey, _ symbol: String, disabled: Bool, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) { Image(systemName: symbol).font(.title3); Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7) }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.borderless).disabled(disabled).help(title)
    }

    // MARK: Lists

    private func toggle(_ e: FSEntry) {
        if selection.contains(e.id) { selection.remove(e.id) } else { selection.insert(e.id) }
    }

    private var listView: some View {
        List(selection: $selection) {
            ForEach(visible) { e in
                if selecting {
                    // Plain rows in Select mode: the List handles taps (iOS Edit mode) and ⌘/⇧-clicks (Mac).
                    row(e).tag(e.id)
                        #if os(macOS)
                        .contentShape(Rectangle()).onTapGesture { toggle(e) }
                        #endif
                        .contextMenu { contextItems(e) }
                } else if e.isDirectory {
                    NavigationLink { FileBrowserView(server: server, path: e.path) } label: { row(e) }
                        .contextMenu { contextItems(e) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeItems(e) }
                } else {
                    Button { open(e) } label: { row(e) }
                        .buttonStyle(.plain)
                        .contextMenu { contextItems(e) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeItems(e) }
                }
            }
        }
        #if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 20) {
                ForEach(visible) { e in
                    if selecting {
                        Button { toggle(e) } label: {
                            tile(e).overlay(alignment: .topTrailing) {
                                Image(systemName: selection.contains(e.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(selection.contains(e.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    .padding(6)
                            }
                            .background(selection.contains(e.id) ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).contextMenu { contextItems(e) }
                    } else if e.isDirectory {
                        NavigationLink { FileBrowserView(server: server, path: e.path) } label: { tile(e) }.buttonStyle(.plain).contextMenu { contextItems(e) }
                    } else {
                        Button { open(e) } label: { tile(e) }.buttonStyle(.plain).contextMenu { contextItems(e) }
                    }
                }
            }.padding()
        }
    }

    private func row(_ e: FSEntry) -> some View {
        let kind = FileKind.of(e)
        return HStack(spacing: 12) {
            Image(systemName: e.isDirectory && GatewayPath.depth(e.path) == 1 ? "externaldrive" : kind.symbol)
                .font(.title3).frame(width: 30).foregroundStyle(e.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).foregroundStyle(.primary).lineLimit(1)
                Text(e.isDirectory ? Self.dateText(e.mtime) : "\(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) · \(Self.dateText(e.mtime))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if busy == e.path { ProgressView() }
        }
    }

    private func tile(_ e: FSEntry) -> some View {
        let kind = FileKind.of(e)
        return VStack(spacing: 8) {
            Image(systemName: e.isDirectory && GatewayPath.depth(e.path) == 1 ? "externaldrive.fill" : (e.isDirectory ? "folder.fill" : kind.symbol))
                .font(.system(size: 44)).frame(height: 56).foregroundStyle(e.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(e.name).font(.footnote).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.primary)
            if !e.isDirectory { Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity).padding(8)
    }

    @ViewBuilder private func contextItems(_ e: FSEntry) -> some View {
        if selecting, selection.contains(e.id), selection.count > 1 {
            // The menu of a selected row acts on the whole selection.
            let items = selected
            let filesOnly = items.filter { !$0.isDirectory }
            Text("\(items.count) selected")
            if path != "/" { Button { clipboard.copy(items, server: server); selecting = false } label: { Label("Copy", systemImage: "doc.on.doc") } }
            if canModify { Button { clipboard.cut(items, server: server); selecting = false } label: { Label("Cut", systemImage: "scissors") } }
            Button { Task { await download(items) } } label: { Label("Download…", systemImage: "arrow.down.circle") }
            if !filesOnly.isEmpty { Button { Task { await share(filesOnly) } } label: { Label("Share…", systemImage: "square.and.arrow.up") } }
            if canModify {
                Divider()
                Button { moving = (items, false) } label: { Label("Move…", systemImage: "folder") }
                Button { moving = (items, true) } label: { Label("Copy to…", systemImage: "doc.on.doc") }
                Button(role: .destructive) { deleting = items } label: { Label("Delete", systemImage: "trash") }
            }
        } else {
            if !e.isDirectory {
                // One "Open" for every file: it picks the right viewer (mpv for MKV/AVI…, the EPUB, comic
                // and archive readers, Quick Look for everything else). Quick Look stays as a separate
                // entry only where Open does something else.
                Button { open(e) } label: { Label("Open", systemImage: "arrow.up.right.square") }
                if opensInViewer(e) { Button { quickLook(e) } label: { Label("Quick Look", systemImage: "eye") } }
                Button { Task { await share([e]) } } label: { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Button { Task { await download([e]) } } label: { Label("Download…", systemImage: "arrow.down.circle") }
            Button { info = e } label: { Label("Info", systemImage: "info.circle") }
            if !selecting && GatewayPath.depth(e.path) > 1 { Button { selecting = true; selection = [e.id] } label: { Label("Select", systemImage: "checkmark.circle") } }
            if GatewayPath.depth(e.path) > 1 {
                Divider()
                Button { clipboard.copy(e, server: server) } label: { Label("Copy", systemImage: "doc.on.doc") }
                if !readOnly { Button { clipboard.cut(e, server: server) } label: { Label("Cut", systemImage: "scissors") } }
                if e.isDirectory, !readOnly, let c = clipboard.pasteable(into: e.path, server: server) {
                    Button { Task { await paste(into: e.path) } } label: { Label(c.cut ? "Paste (move) into folder" : "Paste into folder", systemImage: "doc.on.clipboard") }
                }
            }
            if !readOnly && GatewayPath.depth(e.path) > 1 {
                Divider()
                Button { renameName = e.name; renaming = e } label: { Label("Rename", systemImage: "pencil") }
                Button { moving = ([e], false) } label: { Label("Move…", systemImage: "folder") }
                Button { moving = ([e], true) } label: { Label("Copy to…", systemImage: "doc.on.doc") }
                Button(role: .destructive) { deleting = [e] } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder private func swipeItems(_ e: FSEntry) -> some View {
        if !readOnly && GatewayPath.depth(e.path) > 1 {
            Button(role: .destructive) { deleting = [e] } label: { Label("Delete", systemImage: "trash") }
            Button { renameName = e.name; renaming = e } label: { Label("Rename", systemImage: "pencil") }.tint(.orange)
        }
        Button { info = e } label: { Label("Info", systemImage: "info.circle") }.tint(.gray)
    }

    static func dateText(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    // MARK: Data

    private func load() async {
        guard let client = model.client(for: server) else { error = String(localized: "API key missing"); loading = false; return }
        do {
            let listed = try await client.list(path).entries
            entries = path == "/" ? listed.filter { model.current(server).isVisible(path: $0.path) } : listed
            error = nil
            selection = selection.intersection(entries.map(\.id))
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func opensInViewer(_ e: FSEntry) -> Bool {
        switch FileKind.of(e) {
        case .mpvVideo, .mpvAudio, .epub, .comic, .archive: return true
        default: return false
        }
    }

    private func open(_ e: FSEntry) {
        if opensInViewer(e) { viewer = e } else { quickLook(e) }
    }

    /// Quick Look handles images, PDF, text, Office documents and Apple formats.
    private func quickLook(_ e: FSEntry) {
        Task {
            guard let client = model.client(for: server) else { return }
            busy = e.path; defer { busy = nil }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true).appendingPathComponent(e.name)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { _ = try await client.download(e.path, to: dest); preview = dest } catch { opError = error.localizedDescription }
        }
    }

    /// Fetches the entries (folders recursively) into a fresh temporary folder; returns the top-level
    /// local URLs and the errors met on the way.
    private func fetch(_ items: [FSEntry], purpose: String) async -> (urls: [URL], errors: [String]) {
        guard let client = model.client(for: server) else { return ([], []) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(purpose, isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var urls: [URL] = []; var errors: [String] = []
        func fetchOne(_ e: FSEntry, into dir: URL) async {
            let local = dir.appendingPathComponent(e.name)
            if e.isDirectory {
                try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
                do { for child in try await client.list(e.path).entries { await fetchOne(child, into: local) } }
                catch { errors.append("\(e.name): \(error.localizedDescription)") }
            } else {
                busy = String(localized: "Downloading \(e.name)…")
                do { _ = try await client.download(e.path, to: local) } catch { errors.append("\(e.name): \(error.localizedDescription)") }
            }
        }
        for e in items { await fetchOne(e, into: root); urls.append(root.appendingPathComponent(e.name)) }
        busy = nil
        return (urls.filter { FileManager.default.fileExists(atPath: $0.path) }, errors)
    }

    /// Download: the files (and folders) land where the user chooses through the system's mover.
    private func download(_ items: [FSEntry]) async {
        let r = await fetch(items, purpose: "download")
        if !r.errors.isEmpty { opError = r.errors.joined(separator: "\n") }
        guard !r.urls.isEmpty else { return }
        exportURLs = r.urls; exporting = true
        selecting = false
    }

    private func share(_ items: [FSEntry]) async {
        let r = await fetch(items, purpose: "share")
        if !r.errors.isEmpty { opError = r.errors.joined(separator: "\n") }
        guard !r.urls.isEmpty else { return }
        shareURLs = r.urls
    }

    private func create() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = model.client(for: server) else { return }
        busy = String(localized: "Creating folder…"); defer { busy = nil }
        do { _ = try await client.mkdir(GatewayPath.join(path, name)); await load() } catch { opError = error.localizedDescription }
    }

    private func rename(_ e: FSEntry, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != e.name, let client = model.client(for: server) else { return }
        busy = e.path; defer { busy = nil }
        do { _ = try await client.move(e.path, to: GatewayPath.join(GatewayPath.parent(e.path), n)); await load() } catch { opError = error.localizedDescription }
    }

    /// Moves or copies the entries one after the other; a failure does not stop the others.
    private func transfer(_ items: [FSEntry], to folder: String, copy: Bool) async {
        guard let client = model.client(for: server) else { return }
        var errors: [String] = []
        for (n, e) in items.enumerated() {
            busy = copy ? String(localized: "Copying \(n + 1) of \(items.count)…") : String(localized: "Moving \(n + 1) of \(items.count)…")
            let dest = GatewayPath.join(folder, e.name)
            do {
                if copy { _ = try await client.copy(e.path, to: dest) } else { _ = try await client.move(e.path, to: dest) }
            } catch { errors.append("\(e.name): \(error.localizedDescription)") }
        }
        busy = nil
        if !errors.isEmpty { opError = errors.joined(separator: "\n") }
        selecting = false
        await load()
    }

    private func paste(into folder: String) async {
        guard let client = model.client(for: server) else { return }
        busy = String(localized: "Pasting…"); defer { busy = nil }
        if let err = await clipboard.paste(into: folder, server: server, client: client, progress: { n, total in
            busy = total > 1 ? String(localized: "Pasting \(n) of \(total)…") : String(localized: "Pasting…")
        }) { opError = err }
        await load()
    }

    private func remove(_ items: [FSEntry]) async {
        guard let client = model.client(for: server) else { return }
        var errors: [String] = []
        for (n, e) in items.enumerated() {
            busy = items.count > 1 ? String(localized: "Deleting \(n + 1) of \(items.count)…") : e.path
            do { try await client.delete(e.path) } catch { errors.append("\(e.name): \(error.localizedDescription)") }
        }
        busy = nil
        if !errors.isEmpty { opError = errors.joined(separator: "\n") }
        selecting = false
        await load()
    }

    private func upload(_ urls: [URL]) async {
        guard let client = model.client(for: server) else { return }
        var errors: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            busy = String(localized: "Uploading \(url.lastPathComponent)…")
            do { _ = try await client.upload(fileURL: url, to: GatewayPath.join(path, url.lastPathComponent)) } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        busy = nil
        if !errors.isEmpty { opError = errors.joined(separator: "\n") }
        await load()
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

// MARK: - Info

struct FileInfoView: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    var body: some View {
        let kind = FileKind.of(entry)
        Form {
            Section {
                HStack { Spacer(); Image(systemName: kind.symbol).font(.system(size: 56)).foregroundStyle(.tint); Spacer() }
                LabeledContent("Name", value: entry.name)
                LabeledContent("Type", value: String(localized: String.LocalizationValue(kind.labelKey)))
                if !entry.isDirectory { LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)) }
                LabeledContent("Modified", value: FileBrowserView.dateText(entry.mtime))
                LabeledContent("Path", value: entry.path)
                if let share = entry.path.split(separator: "/").first, let c = model.client(for: server), let a = c.access(forShare: String(share)) {
                    LabeledContent("Permissions", value: a == .readOnly ? String(localized: "Read only") : String(localized: "Read and write"))
                }
            }
        }
        .groupedFormStyle()
        .navigationTitle("Info")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

// MARK: - Folder picker (move / copy destination)

struct FolderPickerView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let title: LocalizedStringKey
    var excluding: Set<String>
    var path: String = "/"
    var copy = false
    let onChoose: (String) -> Void
    var onCancel: () -> Void = {}
    @State private var folders: [FSEntry] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(folders) { f in
                NavigationLink { FolderPickerView(server: server, title: title, excluding: excluding, path: f.path, copy: copy, onChoose: onChoose, onCancel: onCancel) } label: {
                    Label(f.name, systemImage: GatewayPath.depth(f.path) == 1 ? "externaldrive" : "folder")
                }
            }
            if !loading && folders.isEmpty { Text("No subfolders").foregroundStyle(.secondary) }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle(path == "/" ? Text(title) : Text(GatewayPath.name(path)))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
        }
        // The destination is always confirmed explicitly: the bar names the folder that is open and
        // the button does the move/copy *here*. At the root there is no destination yet (a share
        // must be opened first), so the button is disabled and the text says so.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if path == "/" {
                    Text("Open a share, then the folder you want, and confirm with the button.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Text("Destination: \(path)").font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
                Button { onChoose(path) } label: {
                    Label(copy ? "Copy here" : "Move here", systemImage: copy ? "doc.on.doc" : "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(path == "/")
            }
            .padding()
            .background(.bar)
        }
        .task {
            guard let c = model.client(for: server) else { loading = false; return }
            let cfg = model.current(server)
            folders = ((try? await c.list(path).entries) ?? []).filter { $0.isDirectory && !excluding.contains($0.path) && (path != "/" || cfg.isVisible(path: $0.path)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            loading = false
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    init(urls: [URL]) { self.urls = urls }
    init(url: URL) { self.urls = [url] }
    var body: some View {
        VStack(spacing: 20) {
            if urls.count == 1, let url = urls.first {
                Image(systemName: FileKind.of(name: url.lastPathComponent, isDirectory: false).symbol).font(.system(size: 48)).foregroundStyle(.tint)
                Text(url.lastPathComponent).font(.headline).multilineTextAlignment(.center)
                ShareLink(item: url) { Label("Share or save a copy", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "doc.on.doc").font(.system(size: 48)).foregroundStyle(.tint)
                Text("\(urls.count) files").font(.headline)
                Text(urls.map(\.lastPathComponent).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
                ShareLink(items: urls) { Label("Share or save a copy", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }
        }.padding(32)
    }
}
