import SwiftUI
import UnraidGatewayKit

struct ServersView: View {
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @State private var adding = false
    @State private var showSettings = false
    @State private var showWalkthrough = false
    #if os(macOS)
    private let compact = false
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #endif
    @AppStorage("walkthrough.seen") private var walkthroughSeen = false
    /// Navigation path; `-openServer` as a launch argument opens the first server (screenshot automation).
    @State private var path: [ServerConfig] = []
    /// Server whose connection test was requested from a Home Screen quick action.
    @State private var quickTestServer: ServerConfig?
    /// Server whose credentials must be entered (Finder "Sign in…" → unraiddrive://signin?server=ID).
    @State private var signInServer: ServerConfig?
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    private var leadingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    private func promptCredentials(for server: ServerConfig) {
        showWalkthrough = false; showSettings = false; adding = false
        path = [server]
        // Let the navigation settle before presenting, or the sheet is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { signInServer = server }
    }

    @ViewBuilder private var restoreBanner: some View {
        if cloud.shouldOfferRestore(localServers: model.servers) {
            Section {
                Button {
                    Task { await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains() }
                } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "icloud.and.arrow.down") }
            } footer: { Text("A configuration saved by Unraid Drive was found in your iCloud account.") }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No servers", systemImage: "externaldrive.badge.plus")
                    } description: {
                        Text("Add your Unraid server through its unraid-gateway URL and an Unraid API key. Its shares will appear in the Files app.")
                    } actions: {
                        Button("Add server") { adding = true }.buttonStyle(.borderedProminent)
                        if cloud.remoteServerCount > 0 {
                            Button("Restore \(cloud.remoteServerCount) server(s) from iCloud") { Task { await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains() } }.buttonStyle(.bordered)
                        }
                        Button("Try the demo") { Task { await model.addDemo() } }.buttonStyle(.bordered)
                    }
                } else {
                    List {
                        restoreBanner
                        ForEach(model.servers) { server in
                            NavigationLink(value: server) {
                                HStack {
                                    Image(systemName: server.isDemo ? "sparkles" : (server.accessMode == .cloudflareAccess ? "cloud.fill" : "externaldrive.fill")).foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name).font(.headline)
                                        Text(server.isDemo ? String(localized: "Sample data, offline") : (server.username.map { "\($0) · " } ?? "") + server.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            let victims = idx.map { model.servers[$0] }
                            Task { for s in victims { await model.remove(s) } }
                        }
                        Section {
                            Button { adding = true } label: { Label("Add another server", systemImage: "plus.circle") }
                        } footer: {
                            #if os(macOS)
                            Text("Every server you add becomes its own location in the Finder sidebar. Right-click a server to remove it.")
                            #else
                            Text("Every server you add becomes its own location in the Files app. Swipe left on a server to remove it.")
                            #endif
                        }
                    }
                }
            }
            .navigationTitle("Unraid Drive")
            .navigationDestination(for: ServerConfig.self) { ServerDetailView(server: $0) }
            .toolbar {
                ToolbarItemGroup(placement: leadingPlacement) {
                    Button { showWalkthrough = true } label: { Image(systemName: "questionmark.circle") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            #if !os(macOS)
            .fullScreenCover(isPresented: Binding(get: { adding && compact }, set: { adding = $0 })) { AddServerView() }
            #endif
            .sheet(isPresented: Binding(get: { adding && !compact }, set: { adding = $0 })) {
                AddServerView().presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: QuickAction.notification)) { note in
                guard let raw = note.userInfo?["action"] as? String, let action = QuickAction(rawValue: raw) else { return }
                showWalkthrough = false; showSettings = false
                switch action {
                case .openFiles: if let url = URL(string: "shareddocuments://") { openURL(url) }
                case .testConnection: quickTestServer = model.servers.first { !$0.isDemo } ?? model.servers.first
                case .addServer: adding = true
                }
            }
            #endif
            .sheet(isPresented: $showWalkthrough, onDismiss: { walkthroughSeen = true }) {
                WalkthroughView(onTryDemo: model.hasDemo ? nil : { Task { await model.addDemo() } })
            }
            .onAppear {
                #if os(macOS) && DEBUG
                if ProcessInfo.processInfo.arguments.contains("-panelPreview") { openWindow(id: "panelPreview") }
                #endif
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-testConnection") { walkthroughSeen = true; quickTestServer = model.servers.first { !$0.isDemo } ?? model.servers.first }
                // Screenshots without personal data: open the demo server (and its connection test).
                if ProcessInfo.processInfo.arguments.contains("-openDemo"), let demo = model.servers.first(where: { $0.isDemo }) {
                    walkthroughSeen = true; path = [demo]
                    if ProcessInfo.processInfo.arguments.contains("-testDemo") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { quickTestServer = demo } }
                }
                #endif
                if ProcessInfo.processInfo.arguments.contains("-openServer"), let first = model.servers.first {
                    walkthroughSeen = true
                    path = [first]
                } else if !walkthroughSeen {
                    showWalkthrough = true
                }
            }
        }
        .sheet(item: $signInServer) { AddServerView(editing: $0) }
        .sheet(item: $quickTestServer) { ConnectionTestView(server: $0) }
        .onOpenURL { url in
            guard url.scheme == "unraiddrive", url.host == "signin" else { return }
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "server" }?.value
            guard let server = model.servers.first(where: { $0.id == id }) ?? model.servers.first(where: { !$0.isDemo }) else { return }
            promptCredentials(for: server)
        }
        #if os(macOS)
        // The Finder's "Sign in…" launches the app: offer the credentials sheet for a server whose
        // secrets are not in this Mac's Keychain (typical after an iCloud restore without iCloud Keychain).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard signInServer == nil, !adding, let s = model.servers.first(where: { !$0.isDemo && model.client(for: $0) == nil }) else { return }
            promptCredentials(for: s)
        }
        #endif
    }
}
