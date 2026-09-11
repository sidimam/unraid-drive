import SwiftUI
import AVKit
import UnraidGatewayKit

// MARK: - Root

struct TVRootView: View {
    @EnvironmentObject private var model: TVModel
    /// Debug: `-tvOpen <path>` opens that folder of the demo server directly (screenshots).
    private var debugPath: String? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-tvOpen"), a.count > i + 1 { return a[i + 1] }
        #endif
        return nil
    }
    var body: some View {
        NavigationStack {
            if let p = debugPath, let demo = model.servers.first(where: \.isDemo) { TVBrowserView(server: demo, path: p, title: (p as NSString).lastPathComponent.isEmpty ? demo.name : (p as NSString).lastPathComponent) }
            else if model.servers.isEmpty { TVPairView() } else { TVServersView() }
        }
    }
}

/// Servers on this TV + pairing entry point.
struct TVServersView: View {
    @EnvironmentObject private var model: TVModel
    var body: some View {
        List {
            Section {
                ForEach(model.servers) { s in
                    NavigationLink { TVServerHome(server: s) } label: {
                        Label { VStack(alignment: .leading) { Text(s.name).font(.headline); (s.isDemo ? Text("Sample data, offline") : Text(verbatim: (s.username.map { "\($0) · " } ?? "") + (s.url.host ?? ""))).font(.caption).foregroundStyle(.secondary) } }
                        icon: { Image(systemName: s.isDemo ? "sparkles" : "externaldrive.connected.to.line.below") }
                    }
                }
            } header: { Text("Servers") }
            Section {
                NavigationLink { TVPairView() } label: { Label("Pair with iPhone, iPad or Mac", systemImage: "qrcode") }
                if !model.servers.contains(where: \.isDemo) { Button { model.addDemo() } label: { Label("Try the demo", systemImage: "sparkles") } }
            }
        }
        .navigationTitle("Unraid Drive")
    }
}

// MARK: - Pairing

/// Shows a 6-digit code; the phone/Mac app sends the server and its secrets, encrypted with the
/// code, through iCloud Key-Value Storage. Nothing to type on the remote.
struct TVPairView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = TVPairing.generateCode()
    @State private var status: LocalizedStringKey = "Waiting for your other device…"
    @State private var done = false
    private let kvs = NSUbiquitousKeyValueStore.default

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "appletv").font(.system(size: 80)).foregroundStyle(.tint)
            Text("Add a server from another device").font(.title)
            Text("Open Unraid Drive on your iPhone, iPad or Mac, go to Settings › Pair an Apple TV and enter this code. The server and its credentials arrive here encrypted with the code; the TV then connects through your unraid-gateway with your own permissions.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 900)
            Text(code.enumerated().map { $0.offset == 3 ? " \($0.element)" : String($0.element) }.joined())
                .font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.tint)
            Label(status, systemImage: done ? "checkmark.circle.fill" : "hourglass").foregroundStyle(done ? .green : .secondary)
            HStack {
                Button("New code") { code = TVPairing.generateCode() }
                if !model.servers.contains(where: \.isDemo) { Button("Try the demo instead") { model.addDemo(); dismiss() } }
            }
        }
        .padding(60)
        .task { await poll() }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in check() }
    }

    private func poll() async {
        while !Task.isCancelled && !done {
            kvs.synchronize(); check()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func check() {
        guard !done, let data = kvs.data(forKey: TVPairing.kvsKey(code)) else { return }
        do {
            let payload = try TVPairing.decrypt(data, code: code)
            try model.adopt(payload)
            kvs.removeObject(forKey: TVPairing.kvsKey(code)); kvs.synchronize()
            done = true; status = "Paired: \(payload.server.name)"
            Task { try? await Task.sleep(for: .seconds(1.5)); dismiss() }
        } catch {
            status = "Received data could not be decrypted. Check the code and try again."
        }
    }
}

// MARK: - Server home

struct TVServerHome: View {
    @EnvironmentObject private var model: TVModel
    let server: ServerConfig
    @State private var confirmRemove = false
    var body: some View {
        List {
            Section {
                NavigationLink { TVBrowserView(server: server, path: "/", title: server.name) } label: { Label("Browse shares", systemImage: "folder") }
                NavigationLink { TVDashboardView(server: server) } label: { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
            }
            Section {
                Button(role: .destructive) { confirmRemove = true } label: { Label("Remove this server from the TV", systemImage: "trash") }
                    .confirmationDialog("Remove \(server.name)?", isPresented: $confirmRemove) { Button("Remove", role: .destructive) { model.remove(server) } }
            } footer: { Text("Files stay on the NAS. The TV plays photos, music and video in the formats supported by Apple TV (MP4, MOV, M4V, HEVC, AAC, MP3, JPEG, HEIC); other files are listed but cannot be opened here.") }
        }
        .navigationTitle(server.name)
    }
}

// MARK: - Browser

struct TVBrowserView: View {
    @EnvironmentObject private var model: TVModel
    let server: ServerConfig
    let path: String
    let title: String
    @State private var entries: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var playing: FSEntry?
    @State private var viewing: FSEntry?

    private static let video: Set<String> = ["mp4", "m4v", "mov", "hevc", "ts", "m3u8"]
    private static let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "caf"]
    private static let image: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "bmp", "webp"]
    enum Media { case video, audio, image, other }
    static func media(_ e: FSEntry) -> Media {
        let ext = (e.name as NSString).pathExtension.lowercased()
        if video.contains(ext) { return .video }; if audio.contains(ext) { return .audio }; if image.contains(ext) { return .image }; return .other
    }
    static func symbol(_ e: FSEntry) -> String {
        if e.isDirectory { return "folder.fill" }
        switch media(e) { case .video: return "film"; case .audio: return "music.note"; case .image: return "photo"; case .other: return "doc" }
    }

    var body: some View {
        Group {
            if let error { ContentUnavailableView("Cannot load this folder", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if loading && entries.isEmpty { ProgressView() }
            else if entries.isEmpty { ContentUnavailableView("Empty folder", systemImage: "folder") }
            else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 5), spacing: 40) {
                        ForEach(entries) { e in
                            if e.isDirectory {
                                NavigationLink { TVBrowserView(server: server, path: e.path, title: e.name) } label: { tile(e) }.buttonStyle(.card)
                            } else {
                                Button { open(e) } label: { tile(e) }.buttonStyle(.card).disabled(Self.media(e) == .other)
                            }
                        }
                    }.padding(60)
                }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .fullScreenCover(item: $playing) { e in TVPlayerView(server: server, entry: e) }
        .fullScreenCover(item: $viewing) { e in TVImageView(server: server, entry: e) }
    }

    private func tile(_ e: FSEntry) -> some View {
        VStack(spacing: 12) {
            Image(systemName: Self.symbol(e)).font(.system(size: 64)).foregroundStyle(e.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)).frame(height: 90)
            Text(e.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            if !e.isDirectory { Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary) }
        }.frame(width: 300, height: 220).padding(12)
    }

    private func load() async {
        guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); loading = false; return }
        do { entries = try await c.list(path).entries.sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }; error = nil }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func open(_ e: FSEntry) {
        switch Self.media(e) { case .video, .audio: playing = e; case .image: viewing = e; case .other: break }
    }
}

// MARK: - Player / viewer

struct TVPlayerView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        ZStack {
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            else if let error { ContentUnavailableView("Cannot play this file", systemImage: "play.slash", description: Text(error)) }
            else { ProgressView() }
        }
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
            do {
                let req = try await c.mediaRequest(entry.path)
                let asset = AVURLAsset(url: req.url!, options: ["AVURLAssetHTTPHeaderFieldsKey": req.allHTTPHeaderFields ?? [:]])
                let p = AVPlayer(playerItem: AVPlayerItem(asset: asset)); player = p; p.play()
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { player?.pause() }
    }
}

struct TVImageView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea() }
            else if let error { ContentUnavailableView("Cannot show this image", systemImage: "photo", description: Text(error)) }
            else { ProgressView() }
        }
        .onPlayPauseCommand { dismiss() }
        .onExitCommand { dismiss() }
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do { _ = try await c.download(entry.path, to: tmp); image = UIImage(contentsOfFile: tmp.path); try? FileManager.default.removeItem(at: tmp); if image == nil { error = String(localized: "Unsupported image format.") } }
            catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Dashboard

struct TVDashboardView: View {
    @EnvironmentObject private var model: TVModel
    let server: ServerConfig
    @State private var d: Dashboard?
    @State private var error: String?
    var body: some View {
        Group {
            if let d {
                List {
                    Section("System") {
                        LabeledContent("Hostname", value: d.info?.os?.hostname ?? "—")
                        LabeledContent("Unraid", value: d.info?.os?.release ?? "—")
                        if let p = d.metrics?.cpu?.percentTotal { LabeledContent("CPU load", value: String(format: "%.0f %%", p)) }
                        if let p = d.metrics?.memory?.percentTotal { LabeledContent("Memory", value: String(format: "%.0f %%", p)) }
                        if let n = d.notifications?.overview?.unread?.total { LabeledContent("Unread notifications", value: String(n)) }
                    }
                    if let arr = d.array {
                        Section("Array") {
                            LabeledContent("State", value: arr.state)
                            if let b = d.arrayBytes {
                                LabeledContent("Used", value: ByteCountFormatter.string(fromByteCount: b.used, countStyle: .binary) + " / " + ByteCountFormatter.string(fromByteCount: b.total, countStyle: .binary))
                            }
                            if let p = arr.parityCheckStatus, p.running == true { LabeledContent("Parity check", value: "\(p.progress ?? 0) %") }
                        }
                    }
                }
            } else if let error { ContentUnavailableView("Dashboard unavailable", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView() }
        }
        .navigationTitle("Dashboard")
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
            do { d = try await c.graphQL(Dashboard.query, as: Dashboard.self) } catch { self.error = error.localizedDescription }
        }
    }
}
