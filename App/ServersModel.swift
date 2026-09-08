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
        Task { await reimportStaleDomains() }
    }

    /// After servers arrived from iCloud: reload and make sure each has a Files app location.
    func reloadAndRegisterDomains() async {
        reload()
        let existing = (try? await NSFileProviderManager.domains().map(\.identifier.rawValue)) ?? []
        for s in servers where !existing.contains(s.id) { try? await FileProviderDomains.add(s) }
        await reimportStaleDomains()
    }

    /// The system keeps a Files location's database even across an uninstall when the same server
    /// comes back (iCloud restore). Our own item index does not survive, so the two disagree and
    /// stale entries can never be removed. Once per installation, ask the system to rebuild each
    /// location from a fresh enumeration.
    func reimportStaleDomains() async {
        for s in servers {
            let key = "fp.reimported." + s.id
            guard !AppGroup.defaults.bool(forKey: key) else { continue }
            await FileProviderDomains.reimport(s)
            AppGroup.defaults.set(true, forKey: key)
        }
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
    /// Drops the system's cached tree for the location and re-enumerates it from the gateway.
    /// Stronger than `signal`: use after the share layout changed or after a reinstall.
    static func reimport(_ server: ServerConfig) async {
        guard let mgr = NSFileProviderManager(for: domain(for: server)) else { return }
        try? await mgr.reimportItems(below: .rootContainer)
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
