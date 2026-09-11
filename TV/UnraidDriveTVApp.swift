import SwiftUI
import UnraidGatewayKit

/// Unraid Drive for Apple TV: the same servers, reached only through unraid-gateway with the
/// user's own permissions, as a media browser (photos, video, audio) plus the dashboard.
@main
struct UnraidDriveTVApp: App {
    @StateObject private var model = TVModel()
    init() {
        // Same device id as before a reinstall when iCloud remembers it for this Apple TV.
        DeviceIdentity.adoptFromCloudIfNeeded()
    }
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
    /// Servers another device saved in iCloud (Key-Value Storage). tvOS has no iCloud Keychain, so
    /// their credentials can only arrive through pairing: the list is used to tell the user what
    /// is waiting for him and to pre-fill names.
    @Published private(set) var cloudServers: [ServerConfig] = []
    private let store = ServerStore()
    private let keychain = KeychainStore()
    private let kvs = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    init() {
        GatewayClient.component = "Apple TV"
        reload()
        refreshCloud()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCloud() }
        }
        kvs.synchronize()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seedDemo"), !servers.contains(where: \.isDemo) { addDemo() }
        // Debug: `-tvSelectShares documents,media` limits the demo server to those shares (screenshots/tests).
        if let i = args.firstIndex(of: "-tvSelectShares"), args.count > i + 1 {
            setSelectedShares(ServerConfig.demo, args[i + 1].split(separator: ",").map(String.init))
        }
    }
    func reload() { servers = store.all() }
    func refreshCloud() {
        guard let data = kvs.data(forKey: CloudKeys.servers) else { cloudServers = []; return }
        cloudServers = ServerStore.decode(data).filter { !$0.isDemo }
    }
    /// Servers found in iCloud that this TV does not have yet.
    var cloudServersMissingHere: [ServerConfig] {
        cloudServers.filter { c in !servers.contains { $0.id == c.id } }
    }
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
    /// Stores the paired servers with their secrets (local to this TV: tvOS has no iCloud Keychain)
    /// and registers this Apple TV on each gateway. Returns the servers adopted.
    @discardableResult
    func adopt(_ p: PairingPayload) throws -> [ServerConfig] {
        var adopted: [ServerConfig] = []
        for item in p.all {
            try keychain.set(apiKey: item.apiKey, for: item.server.id)
            if let cf = item.cloudflare { try keychain.set(cloudflareToken: cf, for: item.server.id) }
            if let u = item.username, let pw = item.password { try keychain.set(username: u, password: pw, for: item.server.id) }
            var s = item.server; s.username = item.username
            store.upsert(s); adopted.append(s)
        }
        reload()
        // Pairing is the user's own action: register this Apple TV on the gateways.
        for s in adopted { if let c = client(for: s) { Task { _ = try? await c.login(register: true) } } }
        return adopted
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
