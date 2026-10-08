import SwiftUI
import UnraidGatewayKit

/// The window's root (build 42). With a profile configured the app opens straight on its folders;
/// the gear in the explorer header leads to the single Settings sheet, where the profiles (servers,
/// connections, credentials) and the app settings live. Without any profile the first-run screen
/// offers to add one, to restore from iCloud or to try the demo. Deep links, quick actions and the
/// walkthrough are handled here as well.
struct RootView: View {
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @State private var adding = false
    @State private var showSettings = false
    @State private var addOnSettings = false
    @State private var showDiagnostics = false
    @State private var showDashboard = false
    @State private var showWalkthrough = false
    #if os(macOS)
    private let compact = false
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #endif
    /// Server whose connection test was requested from a Home Screen quick action.
    @State private var quickTestServer: ServerConfig?
    /// Server whose credentials must be entered (Finder "Sign in…" → unraiddrive://signin?server=ID).
    @State private var signInServer: ServerConfig?
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    private func promptCredentials(for server: ServerConfig) {
        showWalkthrough = false; showSettings = false; adding = false
        model.select(server)
        // Let the navigation settle before presenting, or the sheet is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { signInServer = server }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let current = model.current {
                    FileBrowserView(server: current, path: "/").id(current.id)
                } else {
                    welcome
                }
            }
            #if !os(macOS)
            .fullScreenCover(isPresented: Binding(get: { adding && compact }, set: { adding = $0 })) { AddServerView() }
            #endif
            .sheet(isPresented: Binding(get: { adding && !compact }, set: { adding = $0 })) {
                AddServerView().presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) { SettingsView(addProfileOnAppear: addOnSettings) }
            .sheet(isPresented: $showDiagnostics) { NavigationStack { DiagnosticsView().environmentObject(model) }.sheetFrame() }
            .sheet(isPresented: $showDashboard) { if let c = model.current { NavigationStack { ServerDetailView(server: c) }.sheetFrame() } }
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
            .onReceive(NotificationCenter.default.publisher(for: AppNavigation.openSettings)) { _ in addOnSettings = false; showSettings = true }
            .onReceive(NotificationCenter.default.publisher(for: AppNavigation.addProfile)) { _ in
                if model.servers.isEmpty { adding = true } else { addOnSettings = true; showSettings = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppNavigation.showFolders)) { _ in showSettings = false }
            .sheet(isPresented: $showWalkthrough, onDismiss: { WalkthroughView.markSeen() }) {
                WalkthroughView(onTryDemo: model.hasDemo ? nil : { Task { await model.addDemo() } })
            }
            .onAppear {
                #if os(macOS) && DEBUG
                if ProcessInfo.processInfo.arguments.contains("-panelPreview") { openWindow(id: "panelPreview") }
                #endif
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-testConnection") { WalkthroughView.markSeen(); quickTestServer = model.servers.first { !$0.isDemo } ?? model.servers.first }
                // `-openDiagnostics`: Settings › Diagnostics and log directly (screenshots, regression).
                if ProcessInfo.processInfo.arguments.contains("-openDiagnostics") { WalkthroughView.markSeen(); showDiagnostics = true }
                // `-openSettings`: the unified Settings sheet (screenshots, regression).
                if ProcessInfo.processInfo.arguments.contains("-openSettings") { WalkthroughView.markSeen(); showSettings = true }
                // Screenshots without personal data: the demo server (and its connection test).
                if ProcessInfo.processInfo.arguments.contains("-openDemo"), let demo = model.servers.first(where: { $0.isDemo }) {
                    WalkthroughView.markSeen(); model.select(demo)
                    if ProcessInfo.processInfo.arguments.contains("-testDemo") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { quickTestServer = demo } }
                }
                #endif
                // `-openServer`: skip the walkthrough and land in the folders (screenshots, regression).
                if ProcessInfo.processInfo.arguments.contains("-openServer") {
                    WalkthroughView.markSeen()
                    if let first = model.servers.first(where: { !$0.isDemo }) ?? model.servers.first { model.select(first) }
                } else if WalkthroughView.shouldShow {
                    showWalkthrough = true
                }
                #if DEBUG
                // `-openDashboard`: the current profile's page (health row, dashboard, System information).
                if ProcessInfo.processInfo.arguments.contains("-openDashboard") { WalkthroughView.markSeen(); showDashboard = true }
                #endif
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

    /// First run: no profile yet.
    private var welcome: some View {
        ContentUnavailableView {
            Label("Welcome to Unraid Drive", systemImage: "externaldrive.badge.plus")
        } description: {
            Text("Add your first profile: the unraid-gateway URL of your Unraid server and an Unraid API key. Its shares then appear here and in the Files app.")
        } actions: {
            Button("Add a profile") { adding = true }.buttonStyle(.borderedProminent)
            if cloud.remoteServerCount > 0 {
                Button("Restore \(cloud.remoteServerCount) server(s) from iCloud") { Task { await model.restoreFromCloudAndRegister() } }.buttonStyle(.bordered)
            }
            Button("Try the demo") { Task { await model.addDemo() } }.buttonStyle(.bordered)
        }
        .navigationTitle("Unraid Drive")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showWalkthrough = true } label: { Label("Help", systemImage: "questionmark.circle") }
            }
        }
    }
}

/// The health dot (build 42): green, yellow for warnings, red for problems, grey while unknown.
struct HealthDot: View {
    let health: ServerHealth?
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 12
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .accessibilityLabel(Text(HealthDot.title(health)))
    }
    private var color: Color {
        switch health?.level {
        case .ok: return .green
        case .warning: return .yellow
        case .error: return .red
        default: return .gray
        }
    }
    static func title(_ h: ServerHealth?) -> LocalizedStringKey {
        switch h?.level {
        case .ok: return "All fine"
        case .warning: return "Warnings"
        case .error: return "Problems"
        default: return "Checking…"
        }
    }
}
