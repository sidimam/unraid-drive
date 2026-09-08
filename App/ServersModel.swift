import Foundation
import FileProvider
import UnraidGatewayKit

/// Owns the server list and keeps File Provider domains in sync with it.
@MainActor
final class ServersModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    private let store = ServerStore()
    private let keychain = KeychainStore()

    init() { reload() }

    func reload() { servers = store.all() }

    func client(for server: ServerConfig) -> GatewayClient? {
        GatewayClientFactory.client(for: server, keychain: keychain)
    }

    var hasDemo: Bool { servers.contains { $0.isDemo } }

    /// Validates the key against the gateway, then persists the server and
    /// registers its File Provider domain so it shows up in the Files app.
    func add(name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login()
        let server = ServerConfig(name: name, url: url, accessMode: cloudflare == nil ? .direct : .cloudflareAccess)
        try keychain.set(apiKey: apiKey, for: server.id)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id) }
        store.upsert(server)
        try await FileProviderDomains.add(server)
        reload()
        return login
    }

    /// Re-validates and replaces the credentials (and mode/name/url) of an existing server,
    /// keeping its id so the Files app location survives.
    func update(_ server: ServerConfig, name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login()
        var updated = server
        updated.name = name; updated.url = url; updated.accessMode = cloudflare == nil ? .direct : .cloudflareAccess
        keychain.remove(for: server.id)
        try keychain.set(apiKey: apiKey, for: server.id)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id) }
        store.upsert(updated)
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
