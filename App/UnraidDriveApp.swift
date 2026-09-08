import SwiftUI
import UnraidGatewayKit

@main
struct UnraidDriveApp: App {
    @StateObject private var servers = ServersModel()

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(servers)
                .environmentObject(servers.cloud)
        }
    }
}
