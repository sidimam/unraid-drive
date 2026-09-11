import SwiftUI
import UnraidGatewayKit
#if os(iOS)
import BackgroundTasks
#endif

@main
struct UnraidDriveApp: App {
    @StateObject private var servers = ServersModel()
    #if os(macOS)
    @StateObject private var feed = ActivityFeed()
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key, store: AppGroup.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(AppIconColor.storageKey, store: AppGroup.defaults) private var iconColor = "default"
    static let refreshTaskID = "com.sdimambro.unraid-drive.refresh"
    #if os(iOS)
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    #endif

    init() {
        NavigationBarStyle.apply()
        #if os(macOS)
        DockPolicy.apply()
        #endif
    }

    var body: some Scene {
        mainWindow
        #if os(macOS)
        MenuBarExtra {
            MenuBarPanel().environmentObject(servers).environmentObject(feed)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
        Window("Offline files", id: "storage") { StorageView().environmentObject(servers).modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system)).tint(AppIconColor.tint(for: iconColor)) }
            .windowResizability(.contentSize)
        Window("Error list", id: "errors") { ErrorListView().environmentObject(feed).modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system)).tint(AppIconColor.tint(for: iconColor)) }
            .windowResizability(.contentSize)
        #if DEBUG
        // `-panelPreview` launch argument: the menu bar panel in a normal window (screenshots).
        Window("Panel preview", id: "panelPreview") { MenuBarPanel().environmentObject(servers).environmentObject(feed).modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system)) }
            .windowResizability(.contentSize)
        #endif
        Window("About Unraid Drive", id: "about") { AboutView().modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system)).tint(AppIconColor.tint(for: iconColor)) }
            .windowResizability(.contentSize)
        #endif
    }

    @SceneBuilder private var mainWindow: some Scene {
        WindowGroup(id: "main") {
            ServersView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
                .task { await seedFromLaunchArguments() }
                .onAppear { (Appearance(rawValue: appearance) ?? .system).applyToWindows() }
                .onChange(of: appearance) { _, v in (Appearance(rawValue: v) ?? .system).applyToWindows() }
                .onChange(of: iconColor) { _, _ in NavigationBarStyle.apply() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        (Appearance(rawValue: appearance) ?? .system).applyToWindows()
                        AppIconColor.apply(iconColor)
                        Task { await servers.signalAllDomains(); await servers.checkHealthAndAlerts() }
                    }
                    if phase == .background { Self.scheduleRefresh() }
                }
                .modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system))
                .tint(AppIconColor.tint(for: iconColor))
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 440)
                .handlesExternalEvents(preferring: ["signin"], allowing: ["*"])
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 760, height: 540)
        #endif
        #if os(iOS)
        // Wake the Files locations from time to time even when the app is not used, so a gateway
        // restart (updates, nightly backups) does not leave them paused until the next launch.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await servers.signalAllDomains()
            await servers.checkHealthAndAlerts()
            Self.scheduleRefresh()
        }
        #endif
    }

    static func scheduleRefresh() {
        #if os(iOS)
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
        #endif
    }

    /// Debug builds only: `-seedServer <url> <apiKey>` adds a Direct server and `-seedDemo` the demo server without touching the UI; `-rebuildDomains` re-registers every location
    /// (used by simulator tests against a local gateway).
    private func seedFromLaunchArguments() async {
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-seedDemo"), !servers.hasDemo { await servers.addDemo() }
        if args.contains("-rebuildDomains") { for s in servers.servers { await FileProviderDomains.rebuild(s) } }
        if args.contains("-testIntent") {
            do {
                let intent = SaveClipboardIntent(); intent.server = ServerStore().all().first { $0.isDemo }.map(ServerEntity.init)
                intent.folder = "documents"; intent.fileName = "Intent test {date}"
                let r = try await intent.perform(); NSLog("intent result: %@", String(describing: r.value ?? ""))
                let l = ListFolderIntent(); l.server = intent.server; l.folder = "documents"
                NSLog("list: %@", String(describing: try await l.perform().value ?? []))
            } catch { NSLog("intent failed: %@", error.localizedDescription) }
        }
        #if os(macOS)
        if args.contains("-evictAll") {   // test hook for the "Free up space" path
            for s in servers.servers { let n = await MaterializedItems.evictAll(for: FileProviderDomains.domain(for: s)); NSLog("evicted %d items for %@", n, s.name) }
        }
        #endif
        guard let i = args.firstIndex(of: "-seedServer"), args.count > i + 2, let url = URL(string: args[i + 1]) else { return }
        guard !servers.servers.contains(where: { $0.url == url }) else { return }
        _ = try? await servers.add(name: "Local test", url: url, apiKey: args[i + 2], cloudflare: nil)
        #endif
    }
}
