import SwiftUI
import UniformTypeIdentifiers
import UnraidGatewayKit

/// "Save to Unraid Drive" share sheet (1.5): files, images, movies, text and links from any app,
/// uploaded through the gateway to a profile + folder the user picks (last destination preselected).
struct ShareView: View {
    @StateObject private var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void

    init(items: [NSExtensionItem], onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ShareModel(items: items))
        self.onDone = onDone; self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.payloads.isEmpty && model.loading { HStack { ProgressView(); Text("Reading the shared items…") } }
                    ForEach(model.payloads) { p in
                        HStack {
                            Image(systemName: p.symbol).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(p.name).lineLimit(1)
                                if let s = p.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                    }
                    if model.hasLink {
                        Toggle("Download what the link points to", isOn: $model.downloadLinks)
                    }
                } header: { Text("Items") }
                Section {
                    if model.servers.isEmpty {
                        Label("No Unraid server configured: add one in Unraid Drive first.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        Picker("Server", selection: $model.serverID) {
                            ForEach(model.servers) { s in Text(s.name).tag(s.id) }
                        }
                        NavigationLink {
                            ShareFolderPicker(server: model.server, initial: model.folder) { model.folder = $0 }
                        } label: { LabeledContent("Folder", value: model.folder.isEmpty ? String(localized: "Choose…") : model.folder) }
                        if !model.recent.isEmpty {
                            Picker("Recent destinations", selection: $model.folder) {
                                ForEach(model.recent, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                } header: { Text("Destination") }
                if model.uploading || model.result != nil {
                    Section {
                        if model.uploading {
                            ProgressView(value: model.progress) { Text(model.current ?? String(localized: "Uploading…")) }
                        }
                        if let r = model.result { Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(r.ok ? .green : .red) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save to Unraid Drive")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.result?.ok == true ? "Done" : "Cancel") { model.result?.ok == true ? onDone() : onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.uploading ? "Saving…" : "Save") { Task { await model.save(); if model.result?.ok == true { try? await Task.sleep(for: .seconds(1)); onDone() } } }
                        .disabled(!model.canSave)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
    }
}

@MainActor
final class ShareModel: ObservableObject {
    struct Payload: Identifiable {
        enum Kind { case file(URL), text(String), link(URL) }
        let id = UUID()
        var kind: Kind
        var name: String
        var subtitle: String?
        var symbol: String {
            switch kind { case .file: return "doc"; case .text: return "text.alignleft"; case .link: return "link" }
        }
    }
    struct Result { var ok: Bool; var message: String }

    @Published var payloads: [Payload] = []
    @Published var loading = true
    @Published var servers: [ServerConfig]
    @Published var serverID: String { didSet { folderChanged() } }
    @Published var folder: String = ""
    @Published var recent: [String] = []
    @Published var downloadLinks = false
    @Published var uploading = false
    @Published var progress: Double = 0
    @Published var current: String?
    @Published var result: Result?
    private let store = ServerStore()
    private let keychain = KeychainStore()
    private static let lastFolderKey = "share.lastFolder."

    var server: ServerConfig? { servers.first { $0.id == serverID } }
    var hasLink: Bool { payloads.contains { if case .link = $0.kind { return true }; return false } }
    var canSave: Bool { !uploading && !payloads.isEmpty && server != nil && !folder.isEmpty && folder != "/" && result?.ok != true }

    init(items: [NSExtensionItem]) {
        let all = ServerStore().all().filter { !$0.isDemo }
        servers = all
        serverID = AppGroup.defaults.string(forKey: "servers.current").flatMap { id in all.first { $0.id == id }?.id } ?? all.first?.id ?? ""
        folderChanged()
        Task { await load(items) }
    }

    private func folderChanged() {
        recent = RecentDestinations.all(server: serverID)
        folder = AppGroup.defaults.string(forKey: Self.lastFolderKey + serverID) ?? recent.first ?? ""
    }

    private func load(_ items: [NSExtensionItem]) async {
        defer { loading = false }
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), let url = await loadURL(p, UTType.fileURL.identifier) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    payloads.append(.init(kind: .file(url), name: url.lastPathComponent, subtitle: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
                } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) || p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || p.hasItemConformingToTypeIdentifier(UTType.data.identifier) && !p.hasItemConformingToTypeIdentifier(UTType.url.identifier) && !p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let type = [UTType.image, UTType.movie, UTType.data].first { p.hasItemConformingToTypeIdentifier($0.identifier) } ?? .data
                    if let url = await loadFile(p, type.identifier) {
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        payloads.append(.init(kind: .file(url), name: url.lastPathComponent, subtitle: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
                    }
                } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(p, UTType.url.identifier) {
                    payloads.append(.init(kind: .link(url), name: url.host ?? url.absoluteString, subtitle: url.absoluteString))
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let text = await loadText(p) {
                    payloads.append(.init(kind: .text(text), name: String(text.prefix(40)).replacingOccurrences(of: "\n", with: " "), subtitle: String(localized: "\(text.count) characters")))
                }
            }
        }
    }

    private func loadURL(_ p: NSItemProvider, _ type: String) async -> URL? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let u = item as? URL { c.resume(returning: u) }
                else if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { c.resume(returning: u) }
                else if let s = item as? String, let u = URL(string: s) { c.resume(returning: u) }
                else { c.resume(returning: nil) }
            }
        }
    }
    private func loadText(_ p: NSItemProvider) async -> String? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let s = item as? String { c.resume(returning: s) }
                else if let d = item as? Data { c.resume(returning: String(data: d, encoding: .utf8)) }
                else if let a = item as? NSAttributedString { c.resume(returning: a.string) }
                else { c.resume(returning: nil) }
            }
        }
    }
    /// Copies the provider's file representation into our temp folder (the system's copy vanishes with the callback).
    private func loadFile(_ p: NSItemProvider, _ type: String) async -> URL? {
        await withCheckedContinuation { c in
            p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { c.resume(returning: nil); return }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true).appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: dest)
                    c.resume(returning: dest)
                } catch { c.resume(returning: nil) }
            }
        }
    }

    func save() async {
        guard let server, let client = GatewayClientFactory.client(for: server, keychain: keychain) else {
            result = .init(ok: false, message: String(localized: "Credentials missing from the Keychain: open Unraid Drive and sign in again.")); return
        }
        uploading = true; result = nil; progress = 0
        defer { uploading = false }
        var done = 0, failed = 0
        var lastError = ""
        let total = payloads.count
        for p in payloads {
            current = p.name
            do {
                switch p.kind {
                case .file(let url):
                    _ = try await client.upload(fileURL: url, to: folder + "/" + url.lastPathComponent, overwrite: false, mtime: nil) { sent, size in
                        Task { @MainActor in self.progress = (Double(done) + (size > 0 ? Double(sent) / Double(size) : 1)) / Double(total) }
                    }
                case .text(let text):
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try text.write(to: tmp, atomically: true, encoding: .utf8)
                    let name = Self.fileName(from: text, ext: text.hasPrefix("#") ? "md" : "txt")
                    _ = try await client.upload(fileURL: tmp, to: folder + "/" + name, overwrite: false)
                    try? FileManager.default.removeItem(at: tmp)
                case .link(let url):
                    if downloadLinks {
                        let (tmp, resp) = try await URLSession.shared.download(from: url)
                        let name = resp.suggestedFilename ?? url.lastPathComponent
                        _ = try await client.upload(fileURL: tmp, to: folder + "/" + (name.isEmpty ? "link" : name), overwrite: false)
                        try? FileManager.default.removeItem(at: tmp)
                    } else {
                        let plist: [String: Any] = ["URL": url.absoluteString]
                        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try data.write(to: tmp)
                        let name = Self.fileName(from: url.host ?? "link", ext: "webloc")
                        _ = try await client.upload(fileURL: tmp, to: folder + "/" + name, overwrite: false)
                        try? FileManager.default.removeItem(at: tmp)
                    }
                }
                done += 1
                ActivityLog.append(ActivityEvent(serverID: server.id, path: folder + "/" + p.name, kind: .upload))
            } catch {
                failed += 1; lastError = error.localizedDescription
                ActivityLog.append(ActivityEvent(serverID: server.id, path: folder + "/" + p.name, kind: .upload, error: error.localizedDescription))
                Diag.error("share", p.name, error)
            }
            progress = Double(done + failed) / Double(total)
        }
        current = nil
        RecentDestinations.record(folder, server: server.id)
        AppGroup.defaults.set(folder, forKey: Self.lastFolderKey + server.id)
        if failed == 0 { result = .init(ok: true, message: String(localized: "\(done) item(s) saved in \(folder).")) }
        else { result = .init(ok: false, message: String(localized: "\(done) saved, \(failed) failed: \(lastError)")) }
        Diag.info("share", "\(done) saved, \(failed) failed → \(server.name) \(folder)")
    }

    static func fileName(from text: String, ext: String) -> String {
        var base = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Note"
        base = base.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.count > 60 { base = String(base.prefix(60)) }
        if base.isEmpty { base = "Note" }
        let stamp = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
        return "\(base) \(stamp).\(ext)".replacingOccurrences(of: ":", with: ".")
    }
}

/// Minimal folder browser for the extension (the app's picker needs the app's model).
struct ShareFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig?
    let initial: String
    let onChoose: (String) -> Void
    @State private var path: String
    @State private var folders: [FSEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var newFolder = false
    @State private var newName = ""

    init(server: ServerConfig?, initial: String, onChoose: @escaping (String) -> Void) {
        self.server = server; self.initial = initial; self.onChoose = onChoose
        _path = State(initialValue: initial.isEmpty ? "/" : initial)
    }

    var body: some View {
        List {
            if path != "/" {
                Button { path = GatewayPath.parent(path); Task { await load() } } label: { Label("Up", systemImage: "arrow.up.left") }
            }
            if loading { HStack { ProgressView(); Text("Loading…") } }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            ForEach(folders) { f in
                Button { path = f.path; Task { await load() } } label: { Label(f.name, systemImage: "folder") }
            }
        }
        .navigationTitle(path == "/" ? Text(server?.name ?? "") : Text(GatewayPath.name(path)))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { newFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }.disabled(path == "/") }
            ToolbarItem(placement: .confirmationAction) { Button("Choose") { onChoose(path); dismiss() }.disabled(path == "/") }
        }
        .alert("New folder", isPresented: $newFolder) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await load() }
    }

    private func load() async {
        guard let server, let c = GatewayClientFactory.client(for: server, keychain: KeychainStore()) else { error = String(localized: "Credentials missing"); loading = false; return }
        loading = true; error = nil
        do { folders = try await c.list(path).entries.filter { $0.isDirectory && server.isVisible(path: $0.path) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func create() async {
        let n = newName.trimmingCharacters(in: .whitespaces); newName = ""
        guard !n.isEmpty, let server, let c = GatewayClientFactory.client(for: server, keychain: KeychainStore()) else { return }
        do { let f = try await c.mkdir(path + "/" + n); path = f.path; await load() } catch { self.error = error.localizedDescription }
    }
}
