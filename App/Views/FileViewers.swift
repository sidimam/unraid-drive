import SwiftUI
import UnraidGatewayKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Viewers for what Quick Look cannot show: mpv for non-Apple media, an EPUB reader, a comic reader
/// and an archive listing. Shared by iPhone, iPad, Vision Pro and Mac.
struct FileViewerSheet: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    var body: some View {
        NavigationStack {
            Group {
                switch FileKind.of(entry) {
                case .epub: EPUBReaderView(server: server, entry: entry)
                case .comic: ComicReaderView(server: server, entry: entry)
                case .archive: ArchiveListView(server: server, entry: entry)
                default: MPVSheetView(server: server, entry: entry)
                }
            }
            .navigationTitle(entry.name)
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

enum ViewerLoader {
    @MainActor static func fetch(_ model: ServersModel, _ server: ServerConfig, _ entry: FSEntry) async throws -> Data {
        guard let c = model.client(for: server) else { throw GatewayError.network(String(localized: "API key missing")) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await c.download(entry.path, to: tmp)
        return try Data(contentsOf: tmp)
    }
}

/// Platform image from raw bytes.
struct DataImage: View {
    let data: Data
    var body: some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { Image(uiImage: ui).resizable().scaledToFit() } else { Image(systemName: "photo") }
        #else
        if let ns = NSImage(data: data) { Image(nsImage: ns).resizable().scaledToFit() } else { Image(systemName: "photo") }
        #endif
    }
}

// MARK: - mpv

struct MPVSheetView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let entry: FSEntry
    @StateObject private var handle = MPVHandle()
    @State private var url: URL?
    @State private var headers: [String: String] = [:]
    @State private var error: String?
    @State private var buffering = true
    @State private var paused = false
    @State private var position: Double = 0
    @State private var duration: Double = 0

    var body: some View {
        #if os(visionOS)
        ContentUnavailableView("Not available on Apple Vision Pro", systemImage: "play.slash", description: Text("This format needs the mpv player, which runs on iPhone, iPad, Mac and Apple TV. Use Quick Look or open the file from the Files app."))
        #else
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                MPVPlayerRepresentable(url: url, headers: headers, handle: handle,
                                       onBuffering: { buffering = $0 },
                                       onProgress: { position = $0; duration = $1 },
                                       onEnd: {},
                                       onError: { error = $0 })
            }
            if let error { ContentUnavailableView("Cannot play this file", systemImage: "play.slash", description: Text(error)) }
            else if buffering { ProgressView().tint(.white) }
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Button { handle.seek(-10) } label: { Image(systemName: "gobackward.10") }
                    Button { handle.togglePause(); paused.toggle() } label: { Image(systemName: paused ? "play.fill" : "pause.fill") }
                    Button { handle.seek(10) } label: { Image(systemName: "goforward.10") }
                    Text(clock(position)).monospacedDigit()
                    ProgressView(value: duration > 0 ? min(max(position / duration, 0), 1) : 0).tint(.white)
                    Text(clock(duration)).monospacedDigit()
                }
                .font(.title3).foregroundStyle(.white).padding(12).background(.black.opacity(0.45), in: Capsule()).padding()
            }
        }
        .frame(minHeight: 320)
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "API key missing"); return }
            do { let req = try await c.mediaRequest(entry.path); headers = req.allHTTPHeaderFields ?? [:]; url = req.url }
            catch { self.error = error.localizedDescription }
        }
        #endif
    }
    private func clock(_ t: Double) -> String {
        let s = Int(t.rounded()); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - EPUB

struct EPUBReaderView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let entry: FSEntry
    @State private var title = ""
    @State private var chapters: [EPUBBook.Chapter] = []
    @State private var index = 0
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Group {
            if let error { ContentUnavailableView("Cannot open this document", systemImage: "book", description: Text(error)) }
            else if loading { ProgressView() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(chapters[index].title).font(.title2.bold())
                        Text(chapters[index].text).font(.body).lineSpacing(4)
                    }.padding().frame(maxWidth: 720).frame(maxWidth: .infinity)
                }
                .id(index)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { index -= 1 } label: { Label("Previous", systemImage: "chevron.left") }.disabled(index == 0)
                        Spacer()
                        Menu { ForEach(chapters.indices, id: \.self) { i in Button(chapters[i].title) { index = i } } } label: { Text("Chapter \(index + 1) of \(chapters.count)") }
                        Spacer()
                        Button { index += 1 } label: { Label("Next", systemImage: "chevron.right") }.disabled(index + 1 >= chapters.count)
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
            }
        }
        .task {
            do {
                let data = try await ViewerLoader.fetch(model, server, entry)
                guard let zip = ZipArchive(data: data) else { error = String(localized: "Unsupported or damaged EPUB."); loading = false; return }
                let book = EPUBBook.parse(zip); title = book.title; chapters = book.chapters
                if chapters.isEmpty { error = String(localized: "This EPUB has no readable text chapters.") }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

// MARK: - Comics (CBZ)

struct ComicReaderView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let entry: FSEntry
    @State private var zip: ZipArchive?
    @State private var pages: [ZipArchive.Entry] = []
    @State private var index = 0
    @State private var error: String?

    var body: some View {
        Group {
            if let error { ContentUnavailableView("Cannot open this document", systemImage: "book.pages", description: Text(error)) }
            else if pages.isEmpty { ProgressView() }
            else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let d = zip?.read(pages[index]) { DataImage(data: d) }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { index -= 1 } label: { Label("Previous", systemImage: "chevron.left") }.disabled(index == 0)
                        Spacer(); Text("Page \(index + 1) of \(pages.count)"); Spacer()
                        Button { index += 1 } label: { Label("Next", systemImage: "chevron.right") }.disabled(index + 1 >= pages.count)
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
                #if os(iOS) || os(visionOS)
                .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                    if v.translation.width < 0, index + 1 < pages.count { index += 1 }
                    if v.translation.width > 0, index > 0 { index -= 1 }
                })
                #endif
            }
        }
        .task {
            do {
                let data = try await ViewerLoader.fetch(model, server, entry)
                guard let z = ZipArchive(data: data) else { error = String(localized: "Unsupported or damaged archive."); return }
                zip = z
                pages = z.entries.filter { ["jpg", "jpeg", "png", "webp", "gif"].contains(($0.name as NSString).pathExtension.lowercased()) && !$0.name.hasPrefix("__MACOSX") }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if pages.isEmpty { error = String(localized: "No pages found in this comic.") }
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Archives

struct ArchiveListView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    let entry: FSEntry
    @State private var entries: [ZipArchive.Entry] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let error { ContentUnavailableView("Cannot open this document", systemImage: "doc.zipper", description: Text(error)) }
            else if !loaded { ProgressView() }
            else if entries.isEmpty { ContentUnavailableView("Empty archive", systemImage: "doc.zipper") }
            else {
                List(entries, id: \.name) { e in
                    HStack { Image(systemName: e.name.hasSuffix("/") ? "folder" : "doc").foregroundStyle(.secondary); Text(e.name).lineLimit(1); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)).foregroundStyle(.secondary).font(.callout) }
                }
            }
        }
        .task {
            do {
                let data = try await ViewerLoader.fetch(model, server, entry)
                guard let z = ZipArchive(data: data) else { error = String(localized: "Unsupported or damaged archive."); loaded = true; return }
                entries = z.entries.filter { !$0.name.hasPrefix("__MACOSX") }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch { self.error = error.localizedDescription }
            loaded = true
        }
    }
}
