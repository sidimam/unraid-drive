import SwiftUI
import UIKit
import CoreGraphics
import UnraidGatewayKit

// MARK: - File kinds

/// What the TV can do with a file, decided by extension. Video/audio in Apple formats use the system
/// player, everything else libmpv; text-like files, PDF, EPUB, comics and archives have viewers of
/// their own; anything else shows its details and, for media, the external-player buttons.
// MARK: - External players (Infuse, VLC)

enum ExternalPlayer: CaseIterable {
    case infuse, vlc
    var name: String { self == .infuse ? "Infuse" : "VLC" }
    var scheme: String { self == .infuse ? "infuse://" : "vlc-x-callback://" }
    var isInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: scheme)!) }
    func open(_ media: URL) {
        let q = media.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let s = self == .infuse ? "infuse://x-callback-url/play?url=\(q)" : "vlc-x-callback://x-callback-url/stream?url=\(q)"
        if let u = URL(string: s) { UIApplication.shared.open(u) }
    }
}

// MARK: - Explorer

/// The file explorer: list or grid, sorting, details, and an opener per file kind.
struct TVBrowserView: View {
    @EnvironmentObject private var model: TVModel
    @ObservedObject private var clipboard = ExplorerClipboard.shared
    let server: ServerConfig
    let path: String
    let title: String
    @State private var entries: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var opened: FSEntry?
    @State private var info: FSEntry?
    @State private var deleting: FSEntry?
    @State private var busy: String?
    @AppStorage("tv.explorer.grid") private var grid = false
    @AppStorage("tv.explorer.sort") private var sortKey = "name"

    private var sorted: [FSEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortKey {
            case "date": return a.mtime > b.mtime
            case "size": return a.size > b.size
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Text(path == "/" ? server.name : path).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !entries.isEmpty { Text("\(entries.count) items").font(.callout).foregroundStyle(.secondary) }
                if let c = clipboard.pasteable(into: path, server: server) {
                    Button { Task { await paste(into: path) } } label: { Label(c.cut ? "Paste (move) \(c.entry.name)" : "Paste \(c.entry.name)", systemImage: "doc.on.clipboard") }
                }
                Menu {
                    Picker("Sort by", selection: $sortKey) {
                        Text("Name").tag("name"); Text("Date").tag("date"); Text("Size").tag("size")
                    }
                } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }
                Button { grid.toggle() } label: { Label(grid ? "List" : "Grid", systemImage: grid ? "list.bullet" : "square.grid.2x2") }
            }
            .buttonStyle(TVPillButtonStyle())
            .padding(.horizontal, 60).padding(.vertical, 16)
            Group {
                if let error { ContentUnavailableView("Cannot load this folder", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if loading && entries.isEmpty { ProgressView() }
                else if entries.isEmpty { ContentUnavailableView("Empty folder", systemImage: "folder") }
                else if grid { gridView } else { listView }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .fullScreenCover(item: $opened) { e in TVFileOpener(server: server, entry: e) }
        .sheet(item: $info) { e in TVFileInfoView(server: server, entry: e) { info = nil; opened = e } }
        .confirmationDialog("Delete?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) { if let d = deleting { Task { await remove(d) } } } label: { Text("Delete \(deleting?.name ?? "")") }
        } message: { Text("The file is removed from the NAS. There is no trash on the gateway.") }
        .overlay(alignment: .bottom) {
            if let busy { HStack { ProgressView(); Text(busy) }.padding(16).background(.regularMaterial, in: Capsule()).padding(40) }
        }
    }

    private func paste(into folder: String) async {
        guard let c = model.client(for: server) else { return }
        busy = String(localized: "Pasting…"); defer { busy = nil }
        if let err = await clipboard.paste(into: folder, server: server, client: c) { error = err }
        await load()
    }

    private func remove(_ e: FSEntry) async {
        guard let c = model.client(for: server) else { return }
        busy = e.name; defer { busy = nil }
        do { try await c.delete(e.path); await load() } catch { self.error = error.localizedDescription }
    }

    private var listView: some View {
        List {
            ForEach(sorted) { e in
                row(e).contextMenu { contextItems(e) }
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 5), spacing: 40) {
                ForEach(sorted) { e in
                    if e.isDirectory {
                        NavigationLink { TVBrowserView(server: server, path: e.path, title: e.name) } label: { tile(e) }.buttonStyle(.card).contextMenu { contextItems(e) }
                    } else {
                        Button { open(e) } label: { tile(e) }.buttonStyle(.card).contextMenu { contextItems(e) }
                    }
                }
            }.padding(60)
        }
    }

    @ViewBuilder private func row(_ e: FSEntry) -> some View {
        let kind = FileKind.of(e)
        if e.isDirectory {
            NavigationLink { TVBrowserView(server: server, path: e.path, title: e.name) } label: { rowLabel(e, kind) }
        } else {
            Button { open(e) } label: { rowLabel(e, kind) }
        }
    }

    private func rowLabel(_ e: FSEntry, _ kind: FileKind) -> some View {
        HStack(spacing: 20) {
            Image(systemName: kind.symbol).font(.title2).frame(width: 44).foregroundStyle(e.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).lineLimit(1)
                Text(e.isDirectory ? Self.dateText(e.mtime) : "\(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) · \(Self.dateText(e.mtime))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(LocalizedStringKey(kind.labelKey)).font(.caption).foregroundStyle(.secondary)
            if e.isDirectory { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
    }

    @ViewBuilder private func contextItems(_ e: FSEntry) -> some View {
        Button { info = e } label: { Label("Info", systemImage: "info.circle") }
        if !e.isDirectory { Button { open(e) } label: { Label("Open", systemImage: "arrow.up.right.square") } }
        if GatewayPath.depth(e.path) > 1 {
            Button { clipboard.copy(e, server: server) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { clipboard.cut(e, server: server) } label: { Label("Cut", systemImage: "scissors") }
            if e.isDirectory, let c = clipboard.pasteable(into: e.path, server: server) {
                Button { Task { await paste(into: e.path) } } label: { Label(c.cut ? "Paste (move) into folder" : "Paste into folder", systemImage: "doc.on.clipboard") }
            }
            Button(role: .destructive) { deleting = e } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func tile(_ e: FSEntry) -> some View {
        let kind = FileKind.of(e)
        return VStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: 64)).foregroundStyle(e.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)).frame(height: 90)
            Text(e.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            if !e.isDirectory { Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary) }
        }.frame(width: 300, height: 220).padding(12)
    }

    static func dateText(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    private func load() async {
        guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); loading = false; return }
        do {
            let cfg = model.current(server)
            entries = try await c.list(path).entries.filter { path != "/" || cfg.isVisible(path: $0.path) }
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func open(_ e: FSEntry) { opened = e }
}

/// Routes a file to its viewer.
struct TVFileOpener: View {
    let server: ServerConfig
    let entry: FSEntry
    var body: some View {
        switch FileKind.of(entry) {
        case .video, .audio: TVPlayerView(server: server, entry: entry)
        case .mpvVideo, .mpvAudio: TVMPVPlayerView(server: server, entry: entry)
        case .image: TVImageView(server: server, entry: entry)
        case .text: TVTextView(server: server, entry: entry)
        case .pdf: TVPDFView(server: server, entry: entry)
        case .epub: TVEPUBView(server: server, entry: entry)
        case .comic: TVComicView(server: server, entry: entry)
        case .archive: TVArchiveView(server: server, entry: entry)
        case .folder, .other: TVFileInfoView(server: server, entry: entry, onOpen: nil)
        }
    }
}

// MARK: - Info

struct TVFileInfoView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    var onOpen: (() -> Void)?
    @State private var externalError: String?

    var body: some View {
        let kind = FileKind.of(entry)
        VStack(spacing: 24) {
            Image(systemName: kind.symbol).font(.system(size: 72)).foregroundStyle(.tint)
            Text(entry.name).font(.title2).multilineTextAlignment(.center).lineLimit(3)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                GridRow { Text("Type").foregroundStyle(.secondary); Text(LocalizedStringKey(kind.labelKey)) }
                if !entry.isDirectory { GridRow { Text("Size").foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)) } }
                GridRow { Text("Modified").foregroundStyle(.secondary); Text(TVBrowserView.dateText(entry.mtime)) }
                GridRow { Text("Path").foregroundStyle(.secondary); Text(entry.path).lineLimit(2) }
            }.font(.callout)
            if kind == .other {
                Text("Cannot open this file on Apple TV. Open it with the Files app on iPhone, iPad or Mac, or in the Finder.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 900)
            }
            HStack(spacing: 20) {
                if kind.hasViewer, let onOpen { Button { onOpen() } label: { Label("Open", systemImage: "play.fill") } }
                if kind.isMedia || kind == .other {
                    ForEach(ExternalPlayer.allCases.filter(\.isInstalled), id: \.name) { p in
                        Button { Task { await openExternal(p) } } label: { Label(String(localized: "Open in \(p.name)"), systemImage: "arrow.up.forward.app") }
                    }
                }
                Button("Close") { dismiss() }
            }
            .buttonStyle(TVPillButtonStyle())
            if kind.isMedia || kind == .other {
                Text("External apps stream through a signed gateway link that carries no headers: behind Cloudflare Access the /media path must be excluded from the Access policy.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 900)
            }
            if let externalError { Label(externalError, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
        }
        .padding(60)
    }

    private func openExternal(_ p: ExternalPlayer) async {
        guard let c = model.client(for: server) else { externalError = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
        do { p.open(try await c.mediaTicketURL(entry.path)) }
        catch GatewayError.notFound { externalError = String(localized: "This needs unraid-gateway 0.6 or later on the server.") }
        catch { externalError = error.localizedDescription }
    }
}

// MARK: - Download helper

enum TVFileLoader {
    static let limit: Int64 = 3 * 1024 * 1024
    /// Downloads a file into a temporary URL (caller removes it).
    @MainActor static func fetch(_ model: TVModel, _ server: ServerConfig, _ entry: FSEntry) async throws -> URL {
        guard let c = model.client(for: server) else { throw GatewayError.network(String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac.")) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + entry.name)
        _ = try await c.download(entry.path, to: tmp)
        return tmp
    }
}

// MARK: - Text

struct TVTextView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var text: String?
    @State private var truncated = false
    @State private var error: String?

    private var monospaced: Bool {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return !["txt", "md", "markdown", "nfo", "text", "rtf", "srt", "sub", "vtt", "readme"].contains(ext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(entry.name).font(.headline).lineLimit(1); Spacer(); Button("Close") { dismiss() }.buttonStyle(TVPillButtonStyle()) }
            if let text {
                ScrollView {
                    Text(text)
                        .font(monospaced ? .system(size: 26, design: .monospaced) : .system(size: 30))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .focusable()
                }
                if truncated { Text("Only the first 3 MB are shown.").font(.footnote).foregroundStyle(.secondary) }
            } else if let error {
                ContentUnavailableView("Cannot open this document", systemImage: "doc.text", description: Text(error))
            } else { ProgressView() }
        }
        .padding(48)
        .onExitCommand { dismiss() }
        .task {
            do {
                let tmp = try await TVFileLoader.fetch(model, server, entry); defer { try? FileManager.default.removeItem(at: tmp) }
                var data = try Data(contentsOf: tmp)
                if data.count > Int(TVFileLoader.limit) { data = data.prefix(Int(TVFileLoader.limit)); truncated = true }
                text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
                if (entry.name as NSString).pathExtension.lowercased() == "rtf", let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) { text = attributed.string }
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - PDF (CoreGraphics; PDFKit is not available on tvOS)

struct TVPDFView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var doc: CGPDFDocument?
    @State private var page = 1
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea() }
            else if let error { ContentUnavailableView("Cannot open this document", systemImage: "doc.richtext", description: Text(error)) }
            else { ProgressView() }
            if let doc {
                VStack { Spacer(); Text("Page \(page) of \(doc.numberOfPages)").font(.caption).padding(8).background(.black.opacity(0.5), in: Capsule()).padding(30) }
            }
        }
        .focusable()
        .onMoveCommand { dir in
            guard let doc else { return }
            if dir == .right, page < doc.numberOfPages { page += 1; render() }
            if dir == .left, page > 1 { page -= 1; render() }
        }
        .onExitCommand { dismiss() }
        .task {
            do {
                let tmp = try await TVFileLoader.fetch(model, server, entry); defer { try? FileManager.default.removeItem(at: tmp) }
                guard let d = CGPDFDocument(tmp as CFURL), d.numberOfPages > 0 else { error = String(localized: "Unsupported or damaged PDF."); return }
                doc = d; render()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func render() {
        guard let doc, let p = doc.page(at: page) else { return }
        let box = p.getBoxRect(.mediaBox)
        let scale = min(3840 / box.width, 2160 / box.height)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        image = renderer.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height); ctx.cgContext.scaleBy(x: scale, y: -scale)
            ctx.cgContext.drawPDFPage(p)
        }
    }
}

// MARK: - EPUB (text reader)

struct TVEPUBView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var chapters: [(title: String, text: String)] = []
    @State private var index = 0
    @State private var bookTitle = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(bookTitle.isEmpty ? entry.name : bookTitle).font(.headline).lineLimit(1)
                    if !chapters.isEmpty { Text("Chapter \(index + 1) of \(chapters.count)").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(TVPillButtonStyle())
            }
            if !chapters.isEmpty {
                ScrollView { Text(chapters[index].text).font(.system(size: 30)).frame(maxWidth: 1400, alignment: .leading).padding(24).focusable() }
                    .id(index)
                Text("Left/right: previous or next chapter").font(.footnote).foregroundStyle(.secondary)
            } else if let error {
                ContentUnavailableView("Cannot open this document", systemImage: "book", description: Text(error))
            } else { ProgressView() }
        }
        .padding(48)
        .onMoveCommand { dir in
            if dir == .right, index + 1 < chapters.count { index += 1 }
            if dir == .left, index > 0 { index -= 1 }
        }
        .onExitCommand { dismiss() }
        .task {
            do {
                let tmp = try await TVFileLoader.fetch(model, server, entry); defer { try? FileManager.default.removeItem(at: tmp) }
                guard let zip = ZipArchive(data: try Data(contentsOf: tmp)) else { error = String(localized: "Unsupported or damaged EPUB."); return }
                let book = EPUBBook.parse(zip)
                bookTitle = book.title
                chapters = book.chapters.map { (title: $0.title, text: $0.text) }
                if chapters.isEmpty { error = String(localized: "This EPUB has no readable text chapters.") }
            } catch { self.error = error.localizedDescription }
        }
    }

}

// MARK: - Comics (CBZ)

struct TVComicView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var zip: ZipArchive?
    @State private var pages: [ZipArchive.Entry] = []
    @State private var index = 0
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea() }
            else if let error { ContentUnavailableView("Cannot open this document", systemImage: "book.pages", description: Text(error)) }
            else { ProgressView() }
            if !pages.isEmpty { VStack { Spacer(); Text("Page \(index + 1) of \(pages.count)").font(.caption).padding(8).background(.black.opacity(0.5), in: Capsule()).padding(30) } }
        }
        .focusable()
        .onMoveCommand { dir in
            if dir == .right, index + 1 < pages.count { index += 1; show() }
            if dir == .left, index > 0 { index -= 1; show() }
        }
        .onExitCommand { dismiss() }
        .task {
            do {
                let tmp = try await TVFileLoader.fetch(model, server, entry); defer { try? FileManager.default.removeItem(at: tmp) }
                guard let z = ZipArchive(data: try Data(contentsOf: tmp)) else { error = String(localized: "Unsupported or damaged archive."); return }
                zip = z
                pages = z.entries.filter { ["jpg", "jpeg", "png", "webp", "gif"].contains(($0.name as NSString).pathExtension.lowercased()) && !$0.name.hasPrefix("__MACOSX") }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if pages.isEmpty { error = String(localized: "No pages found in this comic.") } else { show() }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func show() { image = zip?.read(pages[index]).flatMap(UIImage.init(data:)) }
}

// MARK: - Archives (listing only)

struct TVArchiveView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var entries: [ZipArchive.Entry] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(entry.name).font(.headline).lineLimit(1); Spacer(); Button("Close") { dismiss() }.buttonStyle(TVPillButtonStyle()) }
            if let error { ContentUnavailableView("Cannot open this document", systemImage: "doc.zipper", description: Text(error)) }
            else if !loaded { ProgressView() }
            else if entries.isEmpty { ContentUnavailableView("Empty archive", systemImage: "doc.zipper") }
            else {
                List(entries, id: \.name) { e in
                    HStack { Image(systemName: e.name.hasSuffix("/") ? "folder" : "doc"); Text(e.name).lineLimit(1); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(48)
        .onExitCommand { dismiss() }
        .task {
            do {
                let tmp = try await TVFileLoader.fetch(model, server, entry); defer { try? FileManager.default.removeItem(at: tmp) }
                guard let z = ZipArchive(data: try Data(contentsOf: tmp)) else { error = String(localized: "Unsupported or damaged archive."); loaded = true; return }
                entries = z.entries.filter { !$0.name.hasPrefix("__MACOSX") }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                loaded = true
            } catch { self.error = error.localizedDescription; loaded = true }
        }
    }
}
