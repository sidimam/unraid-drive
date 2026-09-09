#if os(macOS)
import SwiftUI
import AppKit
import FileProvider
import ServiceManagement
import UnraidGatewayKit

// MARK: - Location state

/// State of a server's Finder location as seen by the system.
enum LocationState: Equatable {
    case active, paused, disabled, disconnected, missing, needsCredentials

    var label: LocalizedStringKey {
        switch self {
        case .active: return "Up to date"
        case .paused: return "Sync paused"
        case .disabled: return "Disabled in System Settings"
        case .disconnected: return "Disconnected from the server"
        case .missing: return "Location not registered"
        case .needsCredentials: return "Credentials missing on this Mac"
        }
    }
    var symbol: String {
        switch self {
        case .active: return "checkmark.icloud.fill"
        case .paused: return "pause.circle.fill"
        case .disabled: return "exclamationmark.triangle.fill"
        case .disconnected: return "bolt.horizontal.icloud"
        case .missing: return "questionmark.circle"
        case .needsCredentials: return "key.fill"
        }
    }
    var color: Color {
        switch self {
        case .active: return .green
        case .paused: return .secondary
        case .disabled, .disconnected: return .orange
        case .missing: return .secondary
        case .needsCredentials: return .orange
        }
    }
}

/// "Menu bar only": hide the Dock icon and live as an accessory app, like the other cloud drives.
enum DockPolicy {
    static let key = "menuBarOnly"
    static var menuBarOnly: Bool { AppGroup.defaults.bool(forKey: key) }
    static func apply() {
        NSApplication.shared.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}

extension FileProviderDomains {
    static let pausedKey = "fp.paused"
    static var paused: Bool {
        get { AppGroup.defaults.bool(forKey: pausedKey) }
        set { AppGroup.defaults.set(newValue, forKey: pausedKey) }
    }

    /// Whether the user has enabled the location (System Settings › General › Login Items & Extensions › File Providers).
    static func states() async -> [String: LocationState] {
        guard let domains = try? await NSFileProviderManager.domains() else { return [:] }
        var out: [String: LocationState] = [:]
        for d in domains {
            out[d.identifier.rawValue] = !d.userEnabled ? .disabled : (d.isDisconnected ? (paused ? .paused : .disconnected) : .active)
        }
        return out
    }

    /// Pause = disconnect every location (Finder shows them greyed out); resume reconnects.
    static func setPaused(_ on: Bool, servers: [ServerConfig]) async {
        paused = on
        for s in servers {
            guard let mgr = NSFileProviderManager(for: domain(for: s)) else { continue }
            if on { try? await mgr.disconnect(reason: String(localized: "Paused from the menu bar"), options: [.temporary]) }
            else { try? await mgr.reconnect() }
        }
    }

    /// Opens the System Settings pane where File Provider extensions are enabled.
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?extensionPointIdentifier=com.apple.fileprovider-nonui",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fileprovider-nonui",
        ]
        for c in candidates { if let url = URL(string: c), NSWorkspace.shared.open(url) { return } }
    }

    /// Shows the location in the Finder. `NSWorkspace.open` needs file access the sandbox may not
    /// grant, so fall back to asking the Finder itself to open a window rooted at the folder.
    static func revealInFinder(_ server: ServerConfig) async {
        guard let url = await filesAppURL(server) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        }
    }
}

// MARK: - Activity feed (app side)

/// Reads the shared activity log and refreshes when the extension appends to it.
@MainActor
final class ActivityFeed: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []
    private var observer: UnsafeMutableRawPointer?

    init() {
        reload()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let feed = Unmanaged<ActivityFeed>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in feed.reload() }
        }, ActivityLog.notificationName as CFString, nil, .deliverImmediately)
    }
    deinit { if let observer { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer) } }

    func reload() { events = ActivityLog.recent() }
    func clear() { ActivityLog.clear(); reload() }
    var errors: [ActivityEvent] { events.filter(\.failed) }
}

extension ActivityEvent {
    var symbol: String {
        if failed { return "exclamationmark.circle.fill" }
        switch kind {
        case .download: return "arrow.down.circle"
        case .upload, .create: return "arrow.up.circle"
        case .folder: return "folder.badge.plus"
        case .move: return "arrow.turn.up.right"
        case .delete: return "trash"
        }
    }
    var subtitle: LocalizedStringKey {
        if let error { return "Failed: \(error)" }
        switch kind {
        case .download: return "Downloaded"
        case .upload: return "Uploaded"
        case .create: return "Created"
        case .folder: return "Folder created"
        case .move: return "Moved or renamed"
        case .delete: return "Deleted"
        }
    }
}

// MARK: - Menu bar panel

/// The panel behind the menu bar icon, laid out like the desktop clients of the big cloud drives:
/// a button to open the folder, the sync status, the recent activity, notifications, and a gear menu.
struct MenuBarPanel: View {
    enum Tab: Hashable { case home, activity, notifications }
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var feed: ActivityFeed
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .home
    @State private var states: [String: LocationState] = [:]
    @State private var paused = FileProviderDomains.paused
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(DockPolicy.key, store: AppGroup.defaults) private var menuBarOnly = false
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppIconColor.storageKey, store: AppGroup.defaults) private var iconColor = "default"
    @State private var notifications: [String: Dashboard.Notifications.Overview.Counts] = [:]
    @State private var refreshing = false
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Picker("", selection: $tab) {
                Label("Home", systemImage: "house").tag(Tab.home)
                Label("Activity", systemImage: "arrow.triangle.2.circlepath").tag(Tab.activity)
                Label("Notifications", systemImage: "bell").tag(Tab.notifications)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 8)
            Divider()
            ScrollView {
                switch tab {
                case .home: home
                case .activity: activity(feed.events)
                case .notifications: notificationsView
                }
            }
            .frame(height: 380)
            Divider()
            footer.padding(10)
        }
        .frame(width: 400)
        .tint(Color("AccentColor"))
        .task { await refresh() }
        .onChange(of: menuBarOnly) { _, _ in DockPolicy.apply() }
        .onChange(of: appearance) { _, v in (Appearance(rawValue: v) ?? .system).applyToWindows() }
        .onChange(of: iconColor) { _, v in AppIconColor.apply(v) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
            Text("Unraid Drive").font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
            Spacer()
            Button {
                Task { paused.toggle(); await FileProviderDomains.setPaused(paused, servers: model.servers); await refresh() }
            } label: { Image(systemName: paused ? "play.circle" : "pause.circle").font(.title2) }
            .buttonStyle(.plain).help(paused ? Text("Resume sync") : Text("Pause sync"))
            gear
        }
    }

    private var gear: some View {
        Menu {
            Button("Preferences…") { showMainWindow() }
            Button("Offline files…") { open("storage") }
            Button("Error list…") { open("errors") }
            Divider()
            Button("About Unraid Drive…") { open("about") }
            Link("Help", destination: URL(string: "https://github.com/sidimam/unraid-drive/wiki")!)
            Link("Send feedback", destination: URL(string: "https://github.com/sidimam/unraid-drive/issues")!)
            Divider()
            Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) { Text("Launch at login") }
            Toggle(isOn: $menuBarOnly) { Text("Show only in the menu bar") }
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { a in Label(a.label, systemImage: a.icon).tag(a.rawValue) }
            }
            Picker("Icon colour", selection: $iconColor) {
                ForEach(AppIconColor.all) { c in Text(c.label).tag(c.key) }
            }
            Divider()
            Button("Quit Unraid Drive") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: { Image(systemName: "gearshape").font(.title2) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
    }

    // MARK: Home

    private func state(of s: ServerConfig) -> LocationState {
        if !s.isDemo, model.client(for: s) == nil { return .needsCredentials }
        return states[s.id] ?? .missing
    }

    private var overall: LocationState {
        if model.servers.isEmpty { return .missing }
        if paused { return .paused }
        let all = model.servers.map { state(of: $0) }
        if all.contains(.needsCredentials) { return .needsCredentials }
        if all.contains(.disabled) { return .disabled }
        if all.contains(.disconnected) { return .disconnected }
        if all.contains(.missing) { return .missing }
        return .active
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.servers.isEmpty {
                card {
                    Label("No server configured", systemImage: "externaldrive.badge.questionmark").font(.headline)
                    Text("Add your Unraid server from the preferences; its shares then appear in the Finder sidebar.").foregroundStyle(.secondary)
                    Button("Add server…") { showMainWindow() }.buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(model.servers) { server in
                    Button { Task { await FileProviderDomains.revealInFinder(server) } } label: {
                        Label("Open \(server.name) folder", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                card {
                    HStack(spacing: 10) {
                        Image(systemName: overall.symbol).font(.title).foregroundStyle(overall.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(overall.label).font(.title3.weight(.semibold))
                            Text(statusDetail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if overall == .disabled {
                        Button { FileProviderDomains.openSystemSettings() } label: { Label("Enable in System Settings…", systemImage: "gearshape") }
                    }
                    if overall == .needsCredentials, let s = model.servers.first(where: { state(of: $0) == .needsCredentials }) {
                        Button { signIn(s) } label: { Label("Enter credentials…", systemImage: "key") }
                    }
                    if model.servers.count > 1 {
                        Divider()
                        ForEach(model.servers) { s in
                            let st = state(of: s)
                            HStack { Image(systemName: st.symbol).foregroundStyle(st.color); Text(s.name); Spacer(); Text(st.label).foregroundStyle(.secondary) }.font(.callout)
                        }
                    }
                }
                card {
                    HStack { Text("Recent activity").font(.headline); Spacer(); Button("See all") { tab = .activity }.buttonStyle(.link) }
                    if feed.events.isEmpty {
                        Text("Files you open or change appear here.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(feed.events.prefix(4)) { activityRow($0) }
                    }
                }
            }
        }
        .padding(14)
    }

    private var statusDetail: LocalizedStringKey {
        switch overall {
        case .active: return "The Finder shows your shares; files download when you open them."
        case .paused: return "Nothing is synced until you resume."
        case .disabled: return "Enable Unraid Drive under Login Items & Extensions › File Providers."
        case .disconnected: return "The gateway cannot be reached right now."
        case .missing: return "Open the preferences to register the location."
        case .needsCredentials: return "Enter the API key (and Unraid login) for this server on this Mac."
        }
    }

    private func signIn(_ s: ServerConfig) {
        if let url = URL(string: "unraiddrive://signin?server=\(s.id)") { NSWorkspace.shared.open(url) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Activity

    private func activity(_ events: [ActivityEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                emptyState("checkmark.icloud", "Nothing to show yet", "Files you open or change in the Finder appear here.")
            } else {
                HStack { Text("Sync activity").font(.headline); Spacer(); Button("Clear") { feed.clear() }.buttonStyle(.link) }.padding(.bottom, 6)
                ForEach(events) { e in activityRow(e); Divider() }
            }
        }
        .padding(14)
    }

    private func activityRow(_ e: ActivityEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: e.symbol).font(.title3).foregroundStyle(e.failed ? .red : Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).lineLimit(1)
                Text(e.subtitle).font(.caption).foregroundStyle(e.failed ? .red : .secondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(e.date, style: .time).font(.caption).foregroundStyle(.secondary)
                if let b = e.bytes { Text(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 5)
        .help(Text(verbatim: e.path))
    }

    // MARK: Notifications

    private var notificationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let total = notifications.values.reduce(0) { $0 + ($1.total ?? 0) }
            if total == 0 {
                emptyState("bell.badge", "You're all caught up", "Unread Unraid notifications from your servers appear here.")
            } else {
                ForEach(model.servers.filter { (notifications[$0.id]?.total ?? 0) > 0 }) { s in
                    let n = notifications[s.id]!
                    card {
                        Text(s.name).font(.headline)
                        HStack(spacing: 14) {
                            Label("\(n.total ?? 0) unread", systemImage: "bell")
                            if (n.alert ?? 0) > 0 { Label("\(n.alert ?? 0) alerts", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red) }
                            if (n.warning ?? 0) > 0 { Label("\(n.warning ?? 0) warnings", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        }.font(.callout)
                        Text("Open the Unraid web interface to read them.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !model.servers.isEmpty {
                Button("Refresh") { Task { await loadNotifications() } }.buttonStyle(.link)
            }
        }
        .padding(14)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { showMainWindow() } label: { Label("Open Unraid Drive", systemImage: "macwindow") }
            Spacer()
            if refreshing {
                ProgressView().controlSize(.small)
                Text("Refreshing…").foregroundStyle(.secondary)
            } else if let t = lastRefresh {
                Text("Checked at \(t.formatted(date: .omitted, time: .standard))").foregroundStyle(.secondary)
            }
            Button {
                Task {
                    refreshing = true
                    await model.signalAllDomains()           // ask the system to re-enumerate every location
                    try? await Task.sleep(for: .milliseconds(600))
                    await refresh(); lastRefresh = Date(); refreshing = false
                }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.servers.isEmpty || refreshing)
                .help(Text("Asks the Finder to re-read every location from the gateway and reloads status, activity and notifications."))
        }
        .buttonStyle(.borderless).font(.callout)
    }

    // MARK: Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func emptyState(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Color.accentColor).padding(.top, 30)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding()
    }

    private func refresh() async {
        states = await FileProviderDomains.states()
        paused = FileProviderDomains.paused
        feed.reload()
        await loadNotifications()
    }

    private func loadNotifications() async {
        for s in model.servers where !s.isDemo {
            guard let c = model.client(for: s), let d = try? await c.graphQL(Dashboard.query, as: Dashboard.self) else { continue }
            if let n = d.notifications?.overview?.unread { notifications[s.id] = n }
        }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
        // An accessory app has no Dock icon to click: make sure the window comes to the front.
        DispatchQueue.main.async { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true || $0.isKeyWindow }?.makeKeyAndOrderFront(nil) }
    }
    private func showMainWindow() { open("main") }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("launch at login: \(error)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Offline files window

/// Space used on this Mac by files kept locally (materialised by the system), per server, with a button to evict them.
struct StorageView: View {
    @EnvironmentObject private var model: ServersModel
    @State private var usage: [String: (count: Int, bytes: Int64)] = [:]
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Storage on this Mac").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
            Text("Files you open are kept on disk so they open instantly next time; the system removes them when space runs low. Free the space now if you prefer.").foregroundStyle(.secondary)
            Text("Folders and files with changes still uploading are kept.").font(.callout).foregroundStyle(.secondary)
            ForEach(model.servers) { s in
                let u = usage[s.id]
                HStack {
                    Image(systemName: "externaldrive.connected.to.line.below").font(.title2).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(s.name).font(.headline)
                        Text(u.map { "\($0.count) files · \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))" } ?? "Calculating…").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(working ? "Freeing…" : "Free up space") { Task { await evict(s) } }.disabled(working || (u?.count ?? 0) == 0)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            Spacer()
        }
        .padding(20).frame(minWidth: 520, minHeight: 320)
        .task { await measure() }
    }

    private func measure() async {
        for s in model.servers {
            let domain = FileProviderDomains.domain(for: s)
            let files = await MaterializedItems.list(for: domain).filter { $0.contentType != .folder && $0.itemIdentifier != .rootContainer }
            var bytes: Int64 = 0
            let mgr = NSFileProviderManager(for: domain)
            for item in files {
                // Size on disk of the local copy (documentSize is not reported for materialised items).
                if let url = try? await mgr?.getUserVisibleURL(for: item.itemIdentifier),
                   let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                    bytes += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                } else if let n = item.documentSize??.int64Value { bytes += n }
            }
            usage[s.id] = (files.count, bytes)
        }
    }
    private func evict(_ s: ServerConfig) async {
        working = true; defer { working = false }
        _ = await MaterializedItems.evictAll(for: FileProviderDomains.domain(for: s))
        await measure()
    }
}

/// Collects the items the system currently keeps on disk for a domain.
enum MaterializedItems {
    static func list(for domain: NSFileProviderDomain) async -> [NSFileProviderItem] {
        guard let mgr = NSFileProviderManager(for: domain) else { return [] }
        let enumerator = mgr.enumeratorForMaterializedItems()
        return await withCheckedContinuation { cont in
            let observer = Observer { cont.resume(returning: $0) }
            enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data))
        }
    }
    /// Evicts every materialised file of the domain (folders stay); returns how many were evicted.
    static func evictAll(for domain: NSFileProviderDomain) async -> Int {
        guard let mgr = NSFileProviderManager(for: domain) else { return 0 }
        var n = 0
        for item in await list(for: domain) where item.contentType != .folder && item.itemIdentifier != .rootContainer {
            do { try await mgr.evictItem(identifier: item.itemIdentifier); n += 1 } catch { NSLog("evict %@: %@", item.filename, error.localizedDescription) }
        }
        return n
    }

    private final class Observer: NSObject, NSFileProviderEnumerationObserver {
        var items: [NSFileProviderItem] = []
        let done: ([NSFileProviderItem]) -> Void
        init(done: @escaping ([NSFileProviderItem]) -> Void) { self.done = done }
        func didEnumerate(_ updatedItems: [NSFileProviderItemProtocol]) { items += updatedItems.compactMap { $0 as? NSFileProviderItem } }
        func finishEnumerating(upTo nextPage: NSFileProviderPage?) { done(items) }
        func finishEnumeratingWithError(_ error: Error) { done(items) }
    }
}

// MARK: - Error list window

struct ErrorListView: View {
    @EnvironmentObject private var feed: ActivityFeed
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Error list").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
            if feed.errors.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.icloud.fill").font(.system(size: 56)).foregroundStyle(.green).padding(.top, 30)
                    Text("Everything is fine").font(.headline)
                    Text("Files that could not be uploaded or downloaded are listed here.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            } else {
                List(feed.errors) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(e.name, systemImage: e.symbol).foregroundStyle(.red)
                        Text(e.subtitle).font(.callout).foregroundStyle(.secondary)
                        Text(verbatim: e.path).font(.caption).foregroundStyle(.tertiary)
                        Text(e.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }
            }
            Spacer()
        }
        .padding(20).frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - About window

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Unraid Drive").font(.title.weight(.semibold))
            Text("Version \(version) · File Provider").foregroundStyle(.secondary)
            Text("© 2026 Simone Di Mambro. MIT License.").font(.callout).foregroundStyle(.secondary)
            Text("Your Unraid shares in the Finder, through the unraid-gateway container.").font(.callout).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Privacy", destination: URL(string: "https://github.com/sidimam/unraid-drive/blob/main/PRIVACY.md")!)
                Link("License", destination: URL(string: "https://github.com/sidimam/unraid-drive/blob/main/LICENSE")!)
                Link("Source code", destination: URL(string: "https://github.com/sidimam/unraid-drive")!)
            }.font(.callout)
        }
        .padding(28).frame(width: 380)
    }
}

/// Warning shown on the server page while the Finder location is disabled by the user.
struct LocationStateBanner: View {
    let server: ServerConfig
    @State private var state: LocationState?

    var body: some View {
        Group {
            if state == .disabled {
                Section {
                    Label("The Finder location is disabled. Enable Unraid Drive under System Settings › General › Login Items & Extensions › File Providers.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button { FileProviderDomains.openSystemSettings() } label: { Label("Enable in System Settings…", systemImage: "gearshape") }
                }
            }
        }
        .task { await check() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await check() } }
    }
    private func check() async { state = await FileProviderDomains.states()[server.id] ?? .missing }
}
#endif
