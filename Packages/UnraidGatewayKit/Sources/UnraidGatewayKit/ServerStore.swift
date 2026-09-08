import Foundation

/// Identifiers shared between the app and the File Provider extension.
public enum AppGroup {
    /// Must match the `com.apple.security.application-groups` entitlement of both targets.
    public static let identifier = "group.com.sdimambro.unraid-drive"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// How the app reaches the gateway.
public enum AccessMode: String, Codable, Sendable, CaseIterable {
    /// Plain HTTPS to the gateway (LAN, reverse proxy or Cloudflare Tunnel without Access).
    case direct
    /// Cloudflare Zero Trust in front of the tunnel: every request carries a
    /// service token (`CF-Access-Client-Id` / `CF-Access-Client-Secret`),
    /// the same scheme Unraid Deck uses.
    case cloudflareAccess
    /// Built-in sample server, no network. For App Store review and first looks.
    case demo
}

/// A configured gateway. Secrets (API key, Cloudflare service token) live in the Keychain, not here.
public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: URL
    public var createdAt: Date
    public var accessMode: AccessMode
    /// Last change to name/url/mode; used to resolve conflicts when merging with iCloud.
    public var modifiedAt: Date

    public init(id: String = UUID().uuidString, name: String, url: URL, createdAt: Date = Date(), accessMode: AccessMode = .direct, modifiedAt: Date = Date()) {
        self.id = id; self.name = name; self.url = url; self.createdAt = createdAt; self.accessMode = accessMode; self.modifiedAt = modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        accessMode = try c.decodeIfPresent(AccessMode.self, forKey: .accessMode) ?? .direct
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    public var isDemo: Bool { accessMode == .demo }

    /// The demo server is a fixed, well-known configuration.
    public static let demo = ServerConfig(id: "demo", name: "Demo server", url: DemoGateway.baseURL, createdAt: Date(timeIntervalSince1970: 0), accessMode: .demo)
}

/// Persists the server list in the shared app group defaults so the
/// extension can resolve a File Provider domain to a gateway URL.
public struct ServerStore: Sendable {
    private static let key = "servers.v1"
    public init() {}

    public func all() -> [ServerConfig] {
        guard let data = AppGroup.defaults.data(forKey: Self.key) else { return [] }
        return (try? GatewayJSON.decoder.decode([ServerConfig].self, from: data)) ?? []
    }
    public func server(id: String) -> ServerConfig? {
        all().first { $0.id == id }
    }
    public func save(_ servers: [ServerConfig]) {
        if let data = try? GatewayJSON.encoder.encode(servers) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
    public func upsert(_ server: ServerConfig) {
        var list = all().filter { $0.id != server.id }
        var s = server; s.modifiedAt = Date()
        list.append(s)
        save(list.sorted { $0.createdAt < $1.createdAt })
    }

    /// Encodes/decodes the list for transport (iCloud key-value store, export).
    public static func encode(_ servers: [ServerConfig]) -> Data? { try? GatewayJSON.encoder.encode(servers) }
    public static func decode(_ data: Data) -> [ServerConfig] { (try? GatewayJSON.decoder.decode([ServerConfig].self, from: data)) ?? [] }
    public func remove(id: String) {
        save(all().filter { $0.id != id })
    }
}

/// Builds a ready-to-use client for a stored server, resolving its secrets.
public enum GatewayClientFactory {
    public static func client(for server: ServerConfig, keychain: KeychainStore = KeychainStore()) -> GatewayClient? {
        switch server.accessMode {
        case .demo:
            return GatewayClient(baseURL: server.url, apiKey: DemoGateway.apiKey, session: DemoGateway.session())
        case .direct:
            guard let key = keychain.apiKey(for: server.id) else { return nil }
            return GatewayClient(baseURL: server.url, apiKey: key)
        case .cloudflareAccess:
            guard let key = keychain.apiKey(for: server.id), let token = keychain.cloudflareToken(for: server.id) else { return nil }
            return GatewayClient(baseURL: server.url, apiKey: key, extraHeaders: token.headers)
        }
    }
}
