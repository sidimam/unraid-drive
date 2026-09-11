import SwiftUI
import QuickLook
import UnraidGatewayKit

/// A small in-app browser. Day-to-day file work is meant to happen in the
/// Files app through the File Provider extension; this is a quick look.
struct FileBrowserView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let path: String
    @State private var entries: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var preview: URL?
    @State private var downloading: String?

    var body: some View {
        List {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            ForEach(entries) { e in
                if e.isDirectory {
                    NavigationLink { FileBrowserView(server: server, path: e.path) } label: {
                        Label(e.name, systemImage: GatewayPath.depth(e.path) == 1 ? "externaldrive" : "folder")
                    }
                } else {
                    Button { Task { await open(e) } } label: {
                        HStack {
                            Label(e.name, systemImage: "doc").foregroundStyle(.primary)
                            Spacer()
                            if downloading == e.path { ProgressView() } else {
                                Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).foregroundStyle(.secondary).font(.callout)
                            }
                        }
                    }
                }
            }
            if !loading && entries.isEmpty && error == nil { Text("Empty").foregroundStyle(.secondary) }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle(path == "/" ? "Shares" : GatewayPath.name(path))
        .inlineNavigationTitle()
        .refreshable { await load() }
        .task { await load() }
        .quickLookPreview($preview)
    }

    private func load() async {
        guard let client = model.client(for: server) else { error = "API key missing"; loading = false; return }
        do {
            let listed = try await client.list(path).entries
            entries = path == "/" ? listed.filter { model.current(server).isVisible(path: $0.path) } : listed
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func open(_ e: FSEntry) async {
        guard let client = model.client(for: server) else { return }
        downloading = e.path; defer { downloading = nil }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true).appendingPathComponent(e.name)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { _ = try await client.download(e.path, to: dest); preview = dest } catch { self.error = error.localizedDescription }
    }
}
