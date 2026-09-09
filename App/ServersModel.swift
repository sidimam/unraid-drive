import Foundation
import FileProvider
import UnraidGatewayKit

/// Owns the server list and keeps File Provider domains in sync with it.
@MainActor
final class ServersModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    private let store = ServerStore()
    private let keychain = KeychainStore()
    let cloud = CloudSync()

    init() {
        reload()
        cloud.onRemoteChange = { [weak self] in await self?.reloadAndRegisterDomains() }
        if cloud.enabled { Task { await cloud.pull() } }
        Task { await rebuildDomainsOncePerInstall() }
    }

    /// After servers arrived from iCloud: reload and make sure each has a Files app location.
    func reloadAndRegisterDomains() async {
        reload()
        let existing = (try? await NSFileProviderManager.domains().map(\.identifier.rawValue)) ?? []
        for s in servers where !existing.contains(s.id) { try? await FileProviderDomains.add(s) }
        await rebuildDomainsOncePerInstall()
    }

    /// The system keeps a Files location's database across an uninstall when the same server comes
    /// back (iCloud restore), but the extension's item index, which maps its identifiers to paths,
    /// does not survive. The two then disagree: stale entries can never be removed and re-enumerated
    /// items look like new local files. Once per installation, remove and re-add each location so
    /// the system starts from a clean database that matches the fresh index.
    /// Bump when the app icon changes: the Files app shows the icon it saw when the location was
    /// registered, so the locations are re-registered once for every new icon generation.
    static let iconGeneration = 2

    func rebuildDomainsOncePerInstall() async {
        for s in servers where !s.isDemo {
            let key = "fp.rebuilt.g\(Self.iconGeneration)." + s.id
            guard !AppGroup.defaults.bool(forKey: key) else { continue }
            await FileProviderDomains.rebuild(s)
            AppGroup.defaults.set(true, forKey: key)
        }
    }

    /// First contact with a gateway that hands out stable ids (0.5+): rebuild the Files location
    /// once so items switch from local identifiers to server ids without duplicates.
    func adoptServerIDsIfNeeded(_ server: ServerConfig, entries: [FSEntry]) async {
        guard !server.isDemo, entries.contains(where: { $0.itemID != nil }) else { return }
        let key = "fp.serverIDs." + server.id
        guard !AppGroup.defaults.bool(forKey: key) else { return }
        await FileProviderDomains.rebuild(server)
        AppGroup.defaults.set(true, forKey: key)
    }

    /// Explicit rebuild from the UI (discards local changes not yet uploaded).
    func rebuildDomain(_ server: ServerConfig) async {
        await FileProviderDomains.rebuild(server)
        AppGroup.defaults.set(true, forKey: "fp.rebuilt.g\(Self.iconGeneration)." + server.id)
    }

    func reload() { servers = store.all() }

    func client(for server: ServerConfig) -> GatewayClient? {
        GatewayClientFactory.client(for: server, keychain: keychain)
    }

    var hasDemo: Bool { servers.contains { $0.isDemo } }

    /// Nudges every Files app location to re-check its server (used when the app comes to
    /// the foreground: iOS pauses a domain after a network error and waits for a signal).
    func signalAllDomains() async {
        for s in servers where !s.isDemo { await FileProviderDomains.signal(s) }
    }

    /// Validates the key against the gateway, then persists the server and
    /// registers its File Provider domain so it shows up in the Files app.
    func add(name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?, user: (username: String, password: String)? = nil) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, username: user?.username, password: user?.password, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login()
        var server = ServerConfig(name: name, url: url, accessMode: cloudflare == nil ? .direct : .cloudflareAccess)
        server.username = user?.username
        try keychain.set(apiKey: apiKey, for: server.id, synchronizable: cloud.enabled)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id, synchronizable: cloud.enabled) }
        if let user { try keychain.set(username: user.username, password: user.password, for: server.id, synchronizable: cloud.enabled) }
        store.upsert(server)
        try await FileProviderDomains.add(server)
        reload()
        cloud.push()
        return login
    }

    /// Re-validates and replaces the credentials (and mode/name/url) of an existing server,
    /// keeping its id so the Files app location survives.
    func update(_ server: ServerConfig, name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?, user: (username: String, password: String)? = nil) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, username: user?.username, password: user?.password, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login()
        var updated = server
        updated.name = name; updated.url = url; updated.accessMode = cloudflare == nil ? .direct : .cloudflareAccess
        updated.username = user?.username
        keychain.remove(for: server.id)
        try keychain.set(apiKey: apiKey, for: server.id, synchronizable: cloud.enabled)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id, synchronizable: cloud.enabled) }
        if let user { try keychain.set(username: user.username, password: user.password, for: server.id, synchronizable: cloud.enabled) }
        store.upsert(updated)
        cloud.push()
        if updated.name != server.name {
            // Domain display name is fixed at registration: re-register to rename it.
            try? await FileProviderDomains.remove(server)
            try? await FileProviderDomains.add(updated)
        } else {
            await FileProviderDomains.signal(updated)
        }
        reload()
        return login
    }

    /// Adds the built-in demo server (no network, sample files).
    func addDemo() async {
        let server = ServerConfig.demo
        store.upsert(server)
        try? await FileProviderDomains.add(server)
        reload()
    }

    func remove(_ server: ServerConfig) async {
        try? await FileProviderDomains.remove(server)
        keychain.remove(for: server.id)
        store.remove(id: server.id)
        reload()
        cloud.push()
    }
}

enum FileProviderDomains {
    static func domain(for server: ServerConfig) -> NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(rawValue: server.id), displayName: server.name)
    }
    static func add(_ server: ServerConfig) async throws {
        try await NSFileProviderManager.add(domain(for: server))
    }
    static func remove(_ server: ServerConfig) async throws {
        try await NSFileProviderManager.remove(domain(for: server))
    }
    /// Removes the location (and everything the system cached for it, including our item index)
    /// and registers it again, so the Files app rebuilds the tree from the gateway.
    static func rebuild(_ server: ServerConfig) async {
        try? await remove(server)
        if let dir = AppGroup.containerURL?.appendingPathComponent("FileProvider/\(server.id)", isDirectory: true) {
            try? FileManager.default.removeItem(at: dir)
        }
        for attempt in 0..<5 {
            do { try await add(server); return } catch {
                try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
        }
    }

    /// Asks the system to refresh the domain's root and working set.
    static func signal(_ server: ServerConfig) async {
        guard let mgr = NSFileProviderManager(for: domain(for: server)) else { return }
        try? await mgr.signalEnumerator(for: .rootContainer)
        try? await mgr.signalEnumerator(for: .workingSet)
    }
    /// URL that opens the Files app. Deep-linking straight into a provider folder is not
    /// reliable across iOS versions, so this opens Files' Browse view; the server is listed
    /// under Locations › Unraid Drive.
    static func filesAppURL(_ server: ServerConfig) async -> URL? {
        URL(string: "shareddocuments://")
    }
}
