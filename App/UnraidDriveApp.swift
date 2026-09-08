import SwiftUI
import UnraidGatewayKit

@main
struct UnraidDriveApp: App {
    @StateObject private var servers = ServersModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await servers.signalAllDomains() } }
                }
        }
    }
}
