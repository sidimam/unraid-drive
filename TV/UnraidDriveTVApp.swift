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
    init() {
        GatewayClient.component = "Apple TV"
        reload()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seedDemo"), !servers.contains(where: \.isDemo) { addDemo() }
        // Debug: `-tvSelectShares documents,media` limits the demo server to those shares (screenshots/tests).
        if let i = args.firstIndex(of: "-tvSelectShares"), args.count > i + 1 {
            setSelectedShares(ServerConfig.demo, args[i + 1].split(separator: ",").map(String.init))
        }
    }
    func reload() { servers = store.all() }
    func client(for s: ServerConfig) -> GatewayClient? { GatewayClientFactory.client(for: s, keychain: keychain) }
    func addDemo() { store.upsert(ServerConfig.demo); reload() }
    func remove(_ s: ServerConfig) { keychain.remove(for: s.id); store.remove(id: s.id); reload() }
    func current(_ s: ServerConfig) -> ServerConfig { servers.first { $0.id == s.id } ?? s }
    /// Shares to show on this TV (nil = all). Local to the TV; the pairing brings the phone's choice as a start.
    func setSelectedShares(_ s: ServerConfig, _ shares: [String]?) {
        guard var c = store.server(id: s.id) else { return }
        c.selectedShares = shares; c.modifiedAt = Date()
        store.upsert(c); reload()
    }
    /// Stores a paired server with its secrets (local to this TV: tvOS has no iCloud Keychain).
    func adopt(_ p: PairingPayload) throws {
        try keychain.set(apiKey: p.apiKey, for: p.server.id)
        if let cf = p.cloudflare { try keychain.set(cloudflareToken: cf, for: p.server.id) }
        if let u = p.username, let pw = p.password { try keychain.set(username: u, password: pw, for: p.server.id) }
        var s = p.server; s.username = p.username
        store.upsert(s); reload()
        // Pairing is the user's own action: register this Apple TV on the gateway.
        if let c = client(for: s) { Task { _ = try? await c.login(register: true) } }
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
