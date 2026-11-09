import SwiftUI
import UnraidGatewayKit

// Build 49 — layouts for iPad, Vision Pro and the iPhone Duo.
//
// - Compact width (iPhone, iPhone Duo closed): one column, as before (RootView's NavigationStack).
// - Regular width (iPad, iPhone Duo fully open, Vision Pro): two columns, the shares of the current
//   profile in the sidebar and the folders of the chosen share on the right.
// - Hinge half open (iPhone Duo standing like a small laptop, iOS only): the folders above the
//   fold, a control deck below it (profile and health, where you are, the shares).
//
// The three layouts share one route (the chain of folders from the share down), so opening,
// closing or folding the phone keeps you in the same folder.

/// One step of the explorer's navigation: a folder path. A dedicated type (not a bare String) so a
/// folder link never collides with the List's selection, which is keyed by path.
struct FolderRoute: Hashable {
    let path: String
    init(_ path: String) { self.path = path }

    /// "/media/film/2026" → [/media, /media/film, /media/film/2026].
    static func chain(_ path: String) -> [FolderRoute] { Continuity.chain(path).map(FolderRoute.init) }
}

/// The shares of a profile (the gateway's root listing, minus the ones hidden in Settings).
enum ShareList {
    @MainActor
    static func load(_ model: ServersModel, _ server: ServerConfig) async -> Result<[FSEntry], Error> {
        guard let client = model.client(for: server) else {
            return .failure(NSError(domain: "UnraidDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "API key missing")]))
        }
        do {
            let listed = try await client.list("/").entries
            let shares = listed.filter { $0.isDirectory && model.current(server).isVisible(path: $0.path) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return .success(shares)
        } catch { return .failure(error) }
    }
}

/// The header buttons of the share root (health → dashboard, profile switcher, Settings), shared by
/// the sidebar and the hinge deck.
struct ProfileControls: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    var onDashboard: () -> Void
    var onSelectProfile: (ServerConfig) -> Void

    var body: some View {
        // The dot itself, as in the single-column header (a Label would show its title in the
        // iPadOS toolbar); HealthDot carries the accessibility label.
        Button(action: onDashboard) { HealthDot(health: model.health[server.id]) }
        .help(Text(HealthDot.title(model.health[server.id])))
        if model.servers.count > 1 {
            Menu {
                ForEach(model.servers) { s in
                    Button { onSelectProfile(s) } label: {
                        if s.id == server.id { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                    }
                }
            } label: { Label("Profile", systemImage: "externaldrive") }
        }
        Button { NotificationCenter.default.post(name: AppNavigation.openSettings, object: nil) } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

#if os(iOS) || os(visionOS)
/// Two columns: the shares on the left, the folders of the selected share on the right.
struct SplitExplorer: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @Binding var route: [FolderRoute]
    var onDashboard: () -> Void
    var onSelectProfile: (ServerConfig) -> Void
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ShareSidebar(server: server,
                         selection: Binding(get: { route.first?.path },
                                            set: { p in if let p, p != route.first?.path { route = [FolderRoute(p)] } }),
                         onDashboard: onDashboard, onSelectProfile: onSelectProfile)
                .id(server.id)
        } detail: {
            if let share = route.first {
                NavigationStack(path: Binding(get: { Array(route.dropFirst()) }, set: { route = [share] + $0 })) {
                    FileBrowserView(server: server, path: share.path)
                        .id(server.id + share.path)
                        .navigationDestination(for: FolderRoute.self) { r in FileBrowserView(server: server, path: r.path) }
                }
            } else {
                ContentUnavailableView("Choose a share", systemImage: "externaldrive",
                                       description: Text("Pick a share in the sidebar to browse its folders."))
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// The sidebar of the two-column layout: the shares of the current profile.
struct ShareSidebar: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @Binding var selection: String?
    var onDashboard: () -> Void
    var onSelectProfile: (ServerConfig) -> Void
    @State private var shares: [FSEntry] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List(selection: $selection) {
            Section("Shares") {
                ForEach(shares) { e in
                    Label(e.name, systemImage: "externaldrive").tag(e.path)
                }
            }
        }
        .overlay {
            if loading && shares.isEmpty { ProgressView() }
            else if let error, shares.isEmpty { ContentUnavailableView("Cannot load this folder", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if !loading && shares.isEmpty { ContentUnavailableView("No shares", systemImage: "folder") }
        }
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ProfileControls(server: server, onDashboard: onDashboard, onSelectProfile: onSelectProfile)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        switch await ShareList.load(model, server) {
        case .success(let s): shares = s; error = nil
        case .failure(let e): error = e.localizedDescription
        }
        loading = false
        await model.refreshHealth(server)
    }
}
#endif

#if os(iOS)
/// iPhone Duo half open ("laptop" posture): the explorer above the fold, the control deck below.
/// The fold sits in the middle of the inner display, so the top half takes half the height.
struct HingeDeckLayout<Top: View>: View {
    let server: ServerConfig
    @Binding var route: [FolderRoute]
    var onDashboard: () -> Void
    var onSelectProfile: (ServerConfig) -> Void
    @ViewBuilder var top: Top

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                top
                    .frame(height: max(220, geo.size.height / 2))
                    .clipped()
                Divider()
                HingeControlDeck(server: server, route: $route, onDashboard: onDashboard, onSelectProfile: onSelectProfile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }
}

/// The "keyboard" of the laptop posture: profile and health, the path with a step back, the shares.
struct HingeControlDeck: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @Binding var route: [FolderRoute]
    var onDashboard: () -> Void
    var onSelectProfile: (ServerConfig) -> Void
    @State private var shares: [FSEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Label(server.name, systemImage: "externaldrive.connected.to.line.below").font(.headline).lineLimit(1)
                    Spacer()
                    ProfileControls(server: server, onDashboard: onDashboard, onSelectProfile: onSelectProfile)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                }

                // Where you are: every level is a button that goes back there.
                HStack(spacing: 8) {
                    Button { route.removeLast() } label: { Label("Up", systemImage: "chevron.up") }
                        .buttonStyle(.bordered)
                        .disabled(route.isEmpty)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            crumb(Text(server.name), level: 0)
                            ForEach(Array(route.enumerated()), id: \.offset) { i, r in
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                crumb(Text(GatewayPath.name(r.path)), level: i + 1)
                            }
                        }
                    }
                }

                Text("Shares").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(shares) { e in
                        let current = route.first?.path == e.path
                        Button { route = [FolderRoute(e.path)] } label: {
                            Label(e.name, systemImage: current ? "externaldrive.fill" : "externaldrive")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(current ? .accentColor : .secondary)
                        .controlSize(.large)
                    }
                }
            }
            .padding(16)
        }
        .task(id: server.id) {
            if case .success(let s) = await ShareList.load(model, server) { shares = s }
        }
    }

    private func crumb(_ title: Text, level: Int) -> some View {
        let last = level == route.count
        return Button { route = Array(route.prefix(level)) } label: { title.fontWeight(last ? .semibold : .regular).lineLimit(1) }
            .buttonStyle(.borderless)
            .disabled(last)
    }
}
#endif
