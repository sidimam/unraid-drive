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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        Diag.process = "App"
        Diag.info("app", "launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(ServersModel.currentBuild)) on \(ProcessInfo.processInfo.operatingSystemVersionString) · device \(DeviceIdentity.hasLocalID ? String(DeviceIdentity.id.prefix(8)) : "new") · debug log \(Diag.debugEnabled ? "on" : "off")")
        NavigationBarStyle.apply()
        #if os(macOS)
        DockPolicy.apply()
        #endif
        // After a reinstall on the same hardware, come back to the gateway as the same device.
        DeviceIdentity.adoptFromCloudIfNeeded()
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
            RootView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
                .onAppear { (Appearance(rawValue: appearance) ?? .system).applyToWindows() }
                .onChange(of: appearance) { _, v in (Appearance(rawValue: v) ?? .system).applyToWindows() }
                .onChange(of: iconColor) { _, _ in NavigationBarStyle.apply() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        (Appearance(rawValue: appearance) ?? .system).applyToWindows()
                        AppIconColor.apply(iconColor)
                        Task { await servers.maintainLocationsIfNeeded(); await servers.signalAllDomains(); await servers.checkHealthAndAlerts(); await SyncCoordinator.shared.runDue(trigger: "active") }
                    }
                    if phase == .background { Self.scheduleRefresh(); Self.scheduleSync() }
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
        // 1.5: Photos backup and Downloads sync in the background (processing task: minutes of work).
        .backgroundTask(.appRefresh(Self.syncTaskID)) {
            await SyncCoordinator.shared.runDue(trigger: "background")
            Self.scheduleSync()
        }
        #endif
    }

    static let syncTaskID = "com.sdimambro.unraid-drive.sync"
    /// iOS: a processing task (minutes, network, ideally on power) for Photos backups and Downloads syncs.
    static func scheduleSync() {
        #if os(iOS)
        guard !SyncStore.all().filter(\.isActive).isEmpty else { return }
        let req = BGProcessingTaskRequest(identifier: syncTaskID)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(req)
        #endif
    }

    static func scheduleRefresh() {
        #if os(iOS)
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
        #endif
    }

}
