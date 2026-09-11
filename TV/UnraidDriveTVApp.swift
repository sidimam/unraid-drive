import SwiftUI
import UnraidGatewayKit

/// Unraid Drive for Apple TV: the same servers, reached only through unraid-gateway with the
/// user's own permissions, as a media browser (photos, video, audio) plus the dashboard.
@main
struct UnraidDriveTVApp: App {
    @StateObject private var model = TVModel()
    var body: some Scene {
        WindowGroup {
            TVRootView().environmentObject(model).tint(AppIconColor.tint(for: AppGroup.defaults.string(forKey: AppIconColor.storageKey) ?? "default"))
        }
    }
}

/// Servers on this Apple TV (local store + local Keychain; secrets arrive through pairing).
@MainActor
final class TVModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    private let store = ServerStore()
    private let keychain = KeychainStore()
    init() { reload(); if ProcessInfo.processInfo.arguments.contains("-seedDemo"), !servers.contains(where: \.isDemo) { addDemo() } }
    func reload() { servers = store.all() }
    func client(for s: ServerConfig) -> GatewayClient? { GatewayClientFactory.client(for: s, keychain: keychain) }
    func addDemo() { store.upsert(ServerConfig.demo); reload() }
    func remove(_ s: ServerConfig) { keychain.remove(for: s.id); store.remove(id: s.id); reload() }
    /// Stores a paired server with its secrets (local to this TV: tvOS has no iCloud Keychain).
    func adopt(_ p: PairingPayload) throws {
        try keychain.set(apiKey: p.apiKey, for: p.server.id)
        if let cf = p.cloudflare { try keychain.set(cloudflareToken: cf, for: p.server.id) }
        if let u = p.username, let pw = p.password { try keychain.set(username: u, password: pw, for: p.server.id) }
        var s = p.server; s.username = p.username
        store.upsert(s); reload()
    }
}

/// Minimal local copies of the shared appearance helpers used on the TV.
struct AppIconColor {
    static let storageKey = "iconColor"
    static func tint(for key: String) -> Color {
        switch key {
        case "rosso": return Color(red: 0.86, green: 0.22, blue: 0.22)
        case "blu": return Color(red: 0.24, green: 0.45, blue: 0.90)
        case "teal": return Color(red: 0.10, green: 0.65, blue: 0.65)
        case "viola": return Color(red: 0.52, green: 0.34, blue: 0.90)
        case "grafite": return Color(red: 0.55, green: 0.58, blue: 0.62)
        default: return Color(red: 1.00, green: 0.55, blue: 0.18)
        }
    }
}
