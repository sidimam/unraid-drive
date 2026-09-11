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
    let server: ServerConfig
    let path: String
    @State private var entries: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var search = ""
    @AppStorage("explorer.sort") private var sortKey = "name"
    @AppStorage("explorer.grid") private var grid = false
    @State private var busy: String?
    // Presentation
    @State private var preview: URL?
    @State private var viewer: FSEntry?
    @State private var info: FSEntry?
    @State private var newFolder = false
    @State private var newFolderName = ""
    @State private var renaming: FSEntry?
    @State private var renameName = ""
    @State private var moving: (entry: FSEntry, copy: Bool)?
    @State private var deleting: FSEntry?
    @State private var importing = false
    @State private var shareURL: URL?

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
        .navigationTitle(path == "/" ? server.name : GatewayPath.name(path))
        .inlineNavigationTitle()
        .toolbar { toolbarItems }
        .refreshable { await load() }
        .task { await load() }
        .quickLookPreview($preview)
        .sheet(item: $viewer) { e in FileViewerSheet(server: server, entry: e).sheetFrame() }
        .sheet(item: $info) { e in NavigationStack { FileInfoView(server: server, entry: e) }.sheetFrame() }
        .sheet(isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })) {
            if let m = moving {
                NavigationStack {
                    FolderPickerView(server: server, title: m.copy ? "Copy to" : "Move to", excluding: m.entry.path) { dest in
                        Task { await transfer(m.entry, to: dest, copy: m.copy) }
                    }
                }.sheetFrame()
            }
        }
        .sheet(item: $shareURL) { url in ShareSheet(url: url).sheetFrame() }
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
        .confirmationDialog("Delete?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) { if let d = deleting { Task { await remove(d) } } } label: { Text("Delete \(deleting?.name ?? "")") }
        } message: { Text("The file is removed from the NAS. There is no trash on the gateway.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await upload(urls) } }
        }
        .overlay(alignment: .bottom) {
            if let busy {
                HStack { ProgressView(); Text(busy).font(.callout) }.padding(12).background(.regularMaterial, in: Capsule()).padding()
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
            } label: { Label("View options", systemImage: "arrow.up.arrow.down.circle") }
            if path != "/" && !readOnly {
                Menu {
                    Button { newFolderName = ""; newFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { importing = true } label: { Label("Upload files…", systemImage: "square.and.arrow.up") }
                } label: { Label("Add", systemImage: "plus") }
            }
        }
    }

    // MARK: Lists

    private var listView: some View {
        List {
            ForEach(visible) { e in
                if e.isDirectory {
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
                    if e.isDirectory {
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
        if !e.isDirectory {
            Button { open(e) } label: { Label("Open", systemImage: "arrow.up.right.square") }
            Button { quickLook(e) } label: { Label("Quick Look", systemImage: "eye") }
            if FileKind.of(e).isMedia { Button { viewer = e } label: { Label("Play with mpv", systemImage: "play.rectangle") } }
            Button { Task { await share(e) } } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Button { info = e } label: { Label("Info", systemImage: "info.circle") }
        if !readOnly && GatewayPath.depth(e.path) > 1 {
            Divider()
            Button { renameName = e.name; renaming = e } label: { Label("Rename", systemImage: "pencil") }
            Button { moving = (e, false) } label: { Label("Move…", systemImage: "folder") }
            Button { moving = (e, true) } label: { Label("Copy to…", systemImage: "doc.on.doc") }
            Button(role: .destructive) { deleting = e } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder private func swipeItems(_ e: FSEntry) -> some View {
        if !readOnly && GatewayPath.depth(e.path) > 1 {
            Button(role: .destructive) { deleting = e } label: { Label("Delete", systemImage: "trash") }
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
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func open(_ e: FSEntry) {
        switch FileKind.of(e) {
        case .mpvVideo, .mpvAudio, .epub, .comic, .archive: viewer = e
        default: quickLook(e)
        }
    }

    /// Quick Look handles images, PDF, text, Office documents and Apple formats.
    private func quickLook(_ e: FSEntry) {
        Task {
            guard let client = model.client(for: server) else { return }
            busy = e.path; defer { busy = nil }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true).appendingPathComponent(e.name)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { _ = try await client.download(e.path, to: dest); preview = dest } catch { self.error = error.localizedDescription }
        }
    }

    private func share(_ e: FSEntry) async {
        guard let client = model.client(for: server) else { return }
        busy = e.path; defer { busy = nil }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true).appendingPathComponent(e.name)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { _ = try await client.download(e.path, to: dest); shareURL = dest } catch { self.error = error.localizedDescription }
    }

    private func create() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = model.client(for: server) else { return }
        busy = String(localized: "Creating folder…"); defer { busy = nil }
        do { _ = try await client.mkdir(GatewayPath.join(path, name)); await load() } catch { self.error = error.localizedDescription }
    }

    private func rename(_ e: FSEntry, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != e.name, let client = model.client(for: server) else { return }
        busy = e.path; defer { busy = nil }
        do { _ = try await client.move(e.path, to: GatewayPath.join(GatewayPath.parent(e.path), n)); await load() } catch { self.error = error.localizedDescription }
    }

    private func transfer(_ e: FSEntry, to folder: String, copy: Bool) async {
        guard let client = model.client(for: server) else { return }
        busy = e.path; defer { busy = nil }
        let dest = GatewayPath.join(folder, e.name)
        do {
            if copy { _ = try await client.copy(e.path, to: dest) } else { _ = try await client.move(e.path, to: dest) }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ e: FSEntry) async {
        guard let client = model.client(for: server) else { return }
        busy = e.path; defer { busy = nil }
        do { try await client.delete(e.path); await load() } catch { self.error = error.localizedDescription }
    }

    private func upload(_ urls: [URL]) async {
        guard let client = model.client(for: server) else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            busy = String(localized: "Uploading \(url.lastPathComponent)…")
            do { _ = try await client.upload(fileURL: url, to: GatewayPath.join(path, url.lastPathComponent)) } catch { self.error = error.localizedDescription }
        }
        busy = nil
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
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let title: LocalizedStringKey
    var excluding: String
    var path: String = "/"
    let onChoose: (String) -> Void
    @State private var folders: [FSEntry] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(folders) { f in
                NavigationLink { FolderPickerView(server: server, title: title, excluding: excluding, path: f.path, onChoose: onChoose) } label: {
                    Label(f.name, systemImage: GatewayPath.depth(f.path) == 1 ? "externaldrive" : "folder")
                }
            }
            if !loading && folders.isEmpty { Text("No subfolders").foregroundStyle(.secondary) }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle(path == "/" ? Text(title) : Text(GatewayPath.name(path)))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            if path != "/" { ToolbarItem(placement: .confirmationAction) { Button("Choose") { onChoose(path); dismiss() } } }
        }
        .task {
            guard let c = model.client(for: server) else { loading = false; return }
            let cfg = model.current(server)
            folders = ((try? await c.list(path).entries) ?? []).filter { $0.isDirectory && $0.path != excluding && (path != "/" || cfg.isVisible(path: $0.path)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            loading = false
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: FileKind.of(name: url.lastPathComponent, isDirectory: false).symbol).font(.system(size: 48)).foregroundStyle(.tint)
            Text(url.lastPathComponent).font(.headline).multilineTextAlignment(.center)
            ShareLink(item: url) { Label("Share or save a copy", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
        }.padding(32)
    }
}
