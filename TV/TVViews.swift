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
    /// Debug: `-tvPlayURL <url>` opens the mpv player on any URL (no gateway needed).
    private var debugPlayURL: URL? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-tvPlayURL"), a.count > i + 1 { return URL(string: a[i + 1]) }
        #endif
        return nil
    }
    /// Debug: `-tvOpenFile <path>` opens that demo file in its viewer directly.
    private var debugFile: String? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-tvOpenFile"), a.count > i + 1 { return a[i + 1] }
        #endif
        return nil
    }
    /// Debug: `-tvDashboard` opens the demo server's dashboard directly.
    private var debugDashboard: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-tvDashboard")
        #else
        return false
        #endif
    }
    var body: some View {
        NavigationStack {
            if let u = debugPlayURL { TVMPVDebugPlayer(url: u) }
            else if let f = debugFile, let demo = model.servers.first(where: \.isDemo) {
                TVFileOpener(server: demo, entry: FSEntry(name: (f as NSString).lastPathComponent, path: f, type: .file, size: 0, mtime: Date(), etag: ""))
            }
            else if let p = debugPath, let demo = model.servers.first(where: \.isDemo) { TVBrowserView(server: demo, path: p, title: (p as NSString).lastPathComponent.isEmpty ? demo.name : (p as NSString).lastPathComponent) }
            else if debugDashboard, let demo = model.servers.first(where: \.isDemo) { TVDashboardView(server: demo) }
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
                    // A configured server opens its shares directly; Dashboard, Shares to show and
                    // Remove live behind the gear in the explorer's header.
                    NavigationLink { TVBrowserView(server: s, path: "/", title: s.name) } label: { TVServerRow(server: s) }
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

// MARK: - Buttons

/// Stand-alone buttons on tvOS: with the app tint applied globally, the system style paints the
/// focused button *and* its text in the tint, which makes the label unreadable. This style keeps
/// the text white on the tinted focus background and dark on the resting material.
struct TVPillButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 32).padding(.vertical, 16)
            .background(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.regularMaterial), in: Capsule())
            .foregroundStyle(focused ? Color.white : Color.primary)
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
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
    @State private var paired: [ServerConfig] = []
    private let kvs = NSUbiquitousKeyValueStore.default

    var body: some View {
        if paired.count == 1, let one = paired.first {
            // Right after pairing one server: choose the shares to show on this TV (the phone's choice is the start).
            VStack(spacing: 20) {
                TVSharesView(server: one)
                Button("Done") { dismiss() }.buttonStyle(TVPillButtonStyle()).padding(.bottom, 40)
            }
        } else if paired.count > 1 {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(.green)
                Text("Configuration restored: \(paired.count) servers").font(.title)
                Text(paired.map(\.name).joined(separator: " · ")).foregroundStyle(.secondary)
                Text("Every server keeps the shares chosen on your other device; change them any time from the server's page, Shares to show.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 900)
                Button("Done") { dismiss() }.buttonStyle(TVPillButtonStyle())
            }.padding(60)
        } else {
            pairingView
        }
    }

    /// Servers saved in iCloud by the other devices that this TV does not have yet.
    private var waitingInCloud: [ServerConfig] { model.cloudServersMissingHere }

    private var pairingView: some View {
        VStack(spacing: 28) {
            Image(systemName: waitingInCloud.isEmpty ? "appletv" : "icloud.and.arrow.down").font(.system(size: 80)).foregroundStyle(.tint)
            if waitingInCloud.isEmpty {
                Text("Add a server from another device").font(.title)
                Text("Open Unraid Drive on your iPhone, iPad or Mac, go to Settings › Pair an Apple TV and enter this code. The server and its credentials arrive here encrypted with the code; the TV then connects through your unraid-gateway with your own permissions.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 900)
            } else {
                Text("Configuration found in iCloud: \(waitingInCloud.count) server(s)").font(.title)
                Text(waitingInCloud.map(\.name).joined(separator: " · ")).font(.title3).foregroundStyle(.tint)
                Text("Apple TV cannot read the credentials from iCloud Keychain. Open Unraid Drive on your iPhone, iPad or Mac, go to Settings › Pair an Apple TV, enter this code and send all the servers: the whole configuration arrives here encrypted with the code and this Apple TV registers itself on the gateways again.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 900)
            }
            Text(code.enumerated().map { $0.offset == 3 ? " \($0.element)" : String($0.element) }.joined())
                .font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.tint)
            Label(status, systemImage: done ? "checkmark.circle.fill" : "hourglass").foregroundStyle(done ? .green : .secondary)
            HStack {
                Button("New code") { code = TVPairing.generateCode() }
                if !model.servers.contains(where: \.isDemo) { Button("Try the demo instead") { model.addDemo(); dismiss() } }
            }
            .buttonStyle(TVPillButtonStyle())
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
            let adopted = try model.adopt(payload)
            kvs.removeObject(forKey: TVPairing.kvsKey(code)); kvs.synchronize()
            done = true; status = "Paired: \(adopted.map(\.name).joined(separator: ", "))"
            paired = adopted.map { model.current($0) }
        } catch {
            status = "Received data could not be decrypted. Check the code and try again."
        }
    }
}

// MARK: - Server row / settings

/// A list row whose texts stay readable when tvOS paints the focused row white: the system only
/// recolours `.primary`, and a global tint used to leave the label white on white.
struct TVServerRow: View {
    @Environment(\.isFocused) private var focused
    let server: ServerConfig
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: server.isDemo ? "sparkles" : "externaldrive.connected.to.line.below").font(.title2).frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name).font(.headline)
                (server.isDemo ? Text("Sample data, offline") : Text(verbatim: (server.username.map { "\($0) · " } ?? "") + (server.url.host ?? "")))
                    .font(.caption).opacity(0.7)
            }
            Spacer()
        }
        .foregroundStyle(focused ? Color.black : Color.white)
    }
}

/// Behind the gear of the explorer: dashboard, shares to show, removal.
struct TVServerHome: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    @State private var confirmRemove = false
    var body: some View {
        List {
            Section {
                NavigationLink { TVDashboardView(server: server) } label: { TVMenuRow(title: "Dashboard", symbol: "gauge.with.dots.needle.33percent") }
                NavigationLink { TVSharesView(server: server) } label: { TVMenuRow(title: "Shares to show", symbol: "externaldrive.badge.checkmark") }
            }
            Section {
                Button(role: .destructive) { confirmRemove = true } label: { TVMenuRow(title: "Remove this server from the TV", symbol: "trash", destructive: true) }
                    .confirmationDialog("Remove \(server.name)?", isPresented: $confirmRemove) { Button("Remove", role: .destructive) { model.remove(server); dismiss() } }
            }
        }
        .navigationTitle(Text("Settings") + Text(verbatim: " · \(server.name)"))
    }
}

struct TVMenuRow: View {
    @Environment(\.isFocused) private var focused
    let title: LocalizedStringKey
    let symbol: String
    var destructive = false
    var body: some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(focused ? Color.black : (destructive ? Color.red : Color.white))
    }
}

// MARK: - Shares to show

struct TVSharesView: View {
    @EnvironmentObject private var model: TVModel
    let server: ServerConfig
    @State private var shares: [String] = []
    @State private var error: String?
    @State private var loading = true
    private var current: ServerConfig { model.current(server) }
    private var allSelected: Bool { current.selectedShares == nil }

    var body: some View {
        List {
            Section {
                Toggle("All shares", isOn: Binding(get: { allSelected }, set: { on in model.setSelectedShares(server, on ? nil : shares) }))
                if loading { HStack { ProgressView(); Text("Loading shares…") } }
                else if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                else if shares.isEmpty { Text("No shares are visible for this user.").foregroundStyle(.secondary) }
                ForEach(shares, id: \.self) { share in
                    Toggle(isOn: Binding(get: { current.showsShare(share) }, set: { on in toggle(share, on) })) { Label(share, systemImage: "externaldrive") }
                        .disabled(allSelected)
                }
            } footer: { Text("Only the selected shares are shown on this TV. Your Unraid user's permissions still apply on the gateway.") }
        }
        .navigationTitle("Shares to show")
        .task { await load() }
    }

    private func toggle(_ share: String, _ on: Bool) {
        var selected = current.selectedShares ?? shares
        selected.removeAll { $0.lowercased() == share.lowercased() }
        if on { selected.append(share) }
        model.setSelectedShares(server, shares.filter { s in selected.contains { $0.lowercased() == s.lowercased() } })
    }

    private func load() async {
        guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); loading = false; return }
        do {
            let listed = try await c.list("/").entries.filter(\.isDirectory).map(\.name)
            let stale = (current.selectedShares ?? []).filter { s in !listed.contains { $0.lowercased() == s.lowercased() } }
            shares = listed + stale; error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

// MARK: - Player / viewer

/// Debug-only: the mpv player on an arbitrary URL.
struct TVMPVDebugPlayer: View {
    let url: URL
    @State private var buffering = true
    @State private var error: String?
    @State private var position: Double = 0
    var body: some View {
        ZStack {
            MPVPlayerRepresentable(url: url, onBuffering: { buffering = $0 }, onProgress: { position = $0; _ = $1 }, onEnd: {}, onError: { error = $0 }).ignoresSafeArea()
            VStack { Spacer(); Text(error ?? (buffering ? "buffering…" : String(format: "%.1f s", position))).padding(8).background(.black.opacity(0.5)).padding(40) }
        }
    }
}

struct TVPlayerView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var useMPV = false

    var body: some View {
        ZStack {
            if useMPV { TVMPVPlayerView(server: server, entry: entry) }
            else if let player { VideoPlayer(player: player).ignoresSafeArea() }
            else if let error {
                VStack(spacing: 24) {
                    ContentUnavailableView("Cannot play this file", systemImage: "play.slash", description: Text(error))
                    Button { player?.pause(); player = nil; useMPV = true } label: { Label("Play with the built-in mpv player", systemImage: "play.rectangle") }
                        .buttonStyle(TVPillButtonStyle())
                }
            }
            else { ProgressView() }
        }
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
            do {
                let req = try await c.mediaRequest(entry.path)
                // A media ticket carries its own signature: the stream keeps working after the session
                // token expires (long films, pauses). Headers stay for Cloudflare Access.
                let streamURL = (try? await c.mediaTicketURL(entry.path)) ?? req.url!
                let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": req.allHTTPHeaderFields ?? [:]])
                let item = AVPlayerItem(asset: asset)
                let p = AVPlayer(playerItem: item); player = p; p.play()
                // The system player gives up on codecs it does not know: hand over to mpv.
                for await status in item.publisher(for: \.status).values where status == .failed {
                    error = item.error?.localizedDescription ?? String(localized: "The system player cannot decode this file.")
                    player = nil
                    break
                }
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { player?.pause() }
    }
}

/// libmpv player for everything AVFoundation cannot play. Streams the gateway URL with the app's own
/// headers (mpv's http-header-fields), so Cloudflare Access and the bearer token keep working.
struct TVMPVPlayerView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    let entry: FSEntry
    @State private var url: URL?
    @State private var headers: [String: String] = [:]
    @State private var error: String?
    @State private var buffering = true
    @State private var position: Double = 0
    @State private var duration: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                MPVPlayerRepresentable(url: url, headers: headers,
                                       onBuffering: { buffering = $0 },
                                       onProgress: { position = $0; duration = $1 },
                                       onEnd: { dismiss() },
                                       onError: { error = $0 })
                    .ignoresSafeArea()
            }
            if let error {
                ContentUnavailableView("Cannot play this file", systemImage: "play.slash", description: Text(error))
            } else if buffering {
                VStack(spacing: 16) { ProgressView().scaleEffect(1.5); Text(entry.name).foregroundStyle(.secondary) }
            }
            if error == nil, duration > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Text(Self.clock(position)).monospacedDigit()
                        ProgressView(value: min(max(position / duration, 0), 1)).tint(.white)
                        Text(Self.clock(duration)).monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.white.opacity(buffering ? 0.9 : 0.35))
                    .padding(.horizontal, 80).padding(.bottom, 40)
                }
            }
        }
        .task {
            guard let c = model.client(for: server) else { error = String(localized: "Credentials for this server are missing on the TV. Pair it again from your iPhone, iPad or Mac."); return }
            // mpv sends the same headers as the app (bearer token, Cloudflare Access service token).
            // Before starting it, fetch the first byte with those headers: mpv only reports
            // "unrecognized file format" when a login page or a JSON error answers instead of the file,
            // so the real cause is shown here. The stream itself uses a media ticket (gateway 0.6+),
            // which does not expire with the session token.
            do {
                let req = try await c.mediaRequest(entry.path)
                if let problem = await c.mediaPreflight(req) { error = problem; return }
                headers = req.allHTTPHeaderFields ?? [:]
                url = (try? await c.mediaTicketURL(entry.path)) ?? req.url
            } catch { self.error = error.localizedDescription }
        }
    }

    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded()); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
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
    @State private var health: HealthResponse?
    @State private var healthError: String?
    @State private var error: String?
    private static func isGateway(_ c: Dashboard.Container) -> Bool {
        ([c.image ?? ""] + c.names).joined(separator: " ").lowercased().contains("unraid-gateway")
    }
    var body: some View {
        Group {
            if let d {
                List {
                    Section("unraid-gateway") {
                        LabeledContent("Server URL", value: server.url.host ?? server.url.absoluteString)
                        if let health { LabeledContent("Gateway version", value: health.version ?? "—") }
                        else if let healthError { LabeledContent("Gateway version", value: healthError) }
                        let containers = (d.docker?.containers ?? []).filter { Self.isGateway($0) }
                        if containers.isEmpty {
                            LabeledContent("Container", value: String(localized: "not found in Docker"))
                        } else {
                            ForEach(containers) { c in
                                LabeledContent(c.displayName) {
                                    HStack(spacing: 10) {
                                        Circle().fill(c.state == "RUNNING" ? Color.green : (c.state == "PAUSED" ? Color.orange : Color.gray)).frame(width: 14, height: 14)
                                        Text(c.state.capitalized)
                                        if c.isUpdateAvailable == true { Image(systemName: "arrow.down.circle") }
                                    }
                                }
                                if let img = c.image { LabeledContent("Image", value: img) }
                            }
                        }
                    }
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
            do { health = try await c.health() } catch { healthError = error.localizedDescription }
            do { d = try await c.graphQL(Dashboard.query, as: Dashboard.self) } catch { self.error = error.localizedDescription }
        }
    }
}
