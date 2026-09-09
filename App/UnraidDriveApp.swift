import SwiftUI
import UnraidGatewayKit
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@main
struct UnraidDriveApp: App {
    @StateObject private var servers = ServersModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key, store: AppGroup.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(AppIconColor.storageKey, store: AppGroup.defaults) private var iconColor = "default"
    static let refreshTaskID = "com.sdimambro.unraid-drive.refresh"
    #if os(iOS)
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    #endif

    init() { NavigationBarStyle.apply() }

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
                .task { await seedFromLaunchArguments() }
                .onAppear { (Appearance(rawValue: appearance) ?? .system).applyToWindows() }
                .onChange(of: appearance) { _, v in (Appearance(rawValue: v) ?? .system).applyToWindows() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        (Appearance(rawValue: appearance) ?? .system).applyToWindows()
                        AppIconColor.apply(iconColor)
                        Task { await servers.signalAllDomains() }
                    }
                    if phase == .background { Self.scheduleRefresh() }
                }
                .modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system))
                .tint(Color("AccentColor"))
        }
        #if canImport(BackgroundTasks)
        // Wake the Files locations from time to time even when the app is not used, so a gateway
        // restart (updates, nightly backups) does not leave them paused until the next launch.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await servers.signalAllDomains()
            Self.scheduleRefresh()
        }
        #endif
    }

    static func scheduleRefresh() {
        #if canImport(BackgroundTasks)
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
        #endif
    }

    /// Debug builds only: `-seedServer <url> <apiKey>` adds a Direct server without touching the UI
    /// (used by simulator tests against a local gateway).
    private func seedFromLaunchArguments() async {
        #if DEBUG
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-seedServer"), args.count > i + 2, let url = URL(string: args[i + 1]) else { return }
        guard !servers.servers.contains(where: { $0.url == url }) else { return }
        _ = try? await servers.add(name: "Local test", url: url, apiKey: args[i + 2], cloudflare: nil)
        #endif
    }
}
