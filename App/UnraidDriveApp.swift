import SwiftUI
import UnraidGatewayKit

@main
struct UnraidDriveApp: App {
    @StateObject private var servers = ServersModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key, store: AppGroup.defaults) private var language = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await servers.signalAllDomains() } }
                }
                .task { await seedFromLaunchArguments() }
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .modifier(AppLocaleModifier(language: AppLanguage(rawValue: language) ?? .system))
        }
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
