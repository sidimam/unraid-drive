import SwiftUI
import UnraidGatewayKit

/// Unraid Drive for Apple TV: the same servers, reached only through unraid-gateway with the
/// user's own permissions, as a media browser (photos, video, audio) plus the dashboard.
@main
struct UnraidDriveTVApp: App {
    @StateObject private var model = TVModel()
    init() {
        GatewayClient.component = "Apple TV"
        Diag.process = "Apple TV"
        Diag.info("app", "launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")) on tvOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        // Same device id as before a reinstall when iCloud remembers it for this Apple TV.
        DeviceIdentity.adoptFromCloudIfNeeded()
    }
    var body: some Scene {
        WindowGroup {
            TVRootView().environmentObject(model).tint(AppIconColor.tint(for: AppGroup.defaults.string(forKey: AppIconColor.storageKey) ?? "default"))
        }
    }
}

/// Servers on this Apple TV: profiles with their credentials, from iCloud (1.5.3) or from pairing.
@MainActor
final class TVModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    /// Profiles another device saved in iCloud (Key-Value Storage). Since 1.5.3 they carry their
    /// credentials, so the TV can adopt them directly; a profile saved by an older version arrives
    /// without and still needs pairing.
    @Published private(set) var cloudServers: [ServerConfig] = []
    /// The server the TV opens on (build 42). Persisted; falls back to the first real server.
    @Published private(set) var current: ServerConfig?
    private static let currentKey = "tv.servers.current"
    private let store = ServerStore()
    private let keychain = KeychainStore()
    private let kvs = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    init() {
        GatewayClient.component = "Apple TV"
        store.migrateSecretsFromKeychain(keychain)
        reload()
        refreshCloud()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCloud() }
        }
        kvs.synchronize()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seedDemo"), !servers.contains(where: \.isDemo) { addDemo() }
        #if DEBUG
        // `-seedCloudProfile <url> <apiKey>`: writes a profile into iCloud as another device would
        // (servers.v1 + credentials.v1) to test "Use the iCloud configuration".
        if let i = args.firstIndex(of: "-seedCloudProfile"), args.count > i + 2, let url = URL(string: args[i + 1]) {
            var p = ServerConfig(name: "iCloud test", url: url)
            p.setCredentials(apiKey: args[i + 2], cloudflare: nil, user: nil)
            if let d = ServerStore.encode([p.withoutSecrets]) { kvs.set(d, forKey: CloudKeys.servers) }
            if let d = ProfileCredentials.encode(ProfileCredentials.map([p])) { kvs.set(d, forKey: CloudKeys.credentials) }
            refreshCloud()
        }
        #endif
        // Debug: `-tvSelectShares documents,media` limits the demo server to those shares (screenshots/tests).
        if let i = args.firstIndex(of: "-tvSelectShares"), args.count > i + 1 {
            setSelectedShares(ServerConfig.demo, args[i + 1].split(separator: ",").map(String.init))
        }
    }
    func reload() {
        servers = store.all()
        let id = UserDefaults.standard.string(forKey: Self.currentKey)
        current = servers.first { $0.id == id } ?? servers.first { !$0.isDemo } ?? servers.first
    }
    /// Makes a server the one the TV opens on.
    func select(_ s: ServerConfig) { UserDefaults.standard.set(s.id, forKey: Self.currentKey); reload() }
    func refreshCloud() {
        guard let data = kvs.data(forKey: CloudKeys.servers) else { cloudServers = []; return }
        let creds = kvs.data(forKey: CloudKeys.credentials).map(ProfileCredentials.decode) ?? [:]
        cloudServers = ServerStore.decode(data).filter { !$0.isDemo }.map { s in creds[s.id].map { s.applying($0) } ?? s }
        // Profiles already here: take newer credentials from iCloud (changed on another device).
        var local = store.all(), changed = false
        for i in local.indices {
            guard let c = cloudServers.first(where: { $0.id == local[i].id }) else { continue }
            let merged = local[i].mergingSecrets(from: c)
            if merged != local[i] { local[i] = merged; changed = true }
        }
        if changed { store.save(local); reload(); Diag.info("icloud", "credentials updated from iCloud") }
    }
    /// Profiles in iCloud complete enough to be adopted without pairing.
    var cloudServersReady: [ServerConfig] { cloudServersMissingHere.filter(\.hasCredentials) }
    /// Adopts the complete profiles found in iCloud and registers this Apple TV on each gateway.
    @discardableResult
    func adoptFromCloud() -> [ServerConfig] {
        let ready = cloudServersReady
        for s in ready { store.upsert(s) }
        reload()
        Diag.info("icloud", "adopted \(ready.count) profile(s) from iCloud")
        for s in ready { if let c = client(for: s) { Task { _ = try? await c.login(register: true) } } }
        return ready
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
    /// Stores the paired servers with their credentials in the profile and registers this Apple TV
    /// on each gateway. Returns the servers adopted.
    @discardableResult
    func adopt(_ p: PairingPayload) throws -> [ServerConfig] {
        var adopted: [ServerConfig] = []
        for item in p.all {
            var s = item.server
            let u = item.username.flatMap { u in item.password.map { (username: u, password: $0) } }
            s.setCredentials(apiKey: item.apiKey, cloudflare: item.cloudflare, user: u)
            if u == nil { s.username = item.username }
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
