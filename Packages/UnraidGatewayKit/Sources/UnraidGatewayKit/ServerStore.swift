import Foundation

/// Identifiers shared between the app and the File Provider extension.
public enum AppGroup {
    /// Must match the `com.apple.security.application-groups` entitlement of both targets.
    public static let identifier = "group.com.sdimambro.unraid-drive"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
    public static var defaults: UserDefaults {
        if let d = UserDefaults(suiteName: identifier) { return d }
        // Never expected: without the app group the app and its extension would each keep their
        // own server list and device id. Say so loudly instead of silently diverging.
        if !fallbackReported {
            fallbackReported = true
            Diag.error("appgroup", "UserDefaults(suiteName: \(identifier)) unavailable — falling back to standard defaults")
        }
        return .standard
    }
    nonisolated(unsafe) private static var fallbackReported = false
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

/// A configured gateway — a "profile". Since 1.5.3 the profile carries its own credentials (Unraid
/// API key, Cloudflare Access service token, Unraid user and password): they live with the profile in
/// the app group and travel with it through iCloud (Key-Value Store), so a profile restored on a new or
/// reinstalled device is complete. Until 1.5.2 they were in the Keychain and depended on iCloud
/// Keychain carrying each item, which often did not happen; `ServerStore.migrateSecretsFromKeychain()`
/// moves the old items into the profile.
public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: URL
    public var createdAt: Date
    public var accessMode: AccessMode
    /// Last change to name/url/mode; used to resolve conflicts when merging with iCloud.
    public var modifiedAt: Date
    /// Unraid user name (optional per-user access).
    public var username: String?
    /// Credentials of the profile (1.5.3): never written to logs nor to the readable servers.json.
    public var apiKey: String?
    public var cloudflareClientID: String?
    public var cloudflareClientSecret: String?
    public var password: String?
    /// When the credentials last changed (merging copies from iCloud keeps the newest set).
    public var secretsModifiedAt: Date?
    /// Shares the user chose to see (Files app, Finder, Shortcuts, Apple TV). `nil` = every share the
    /// gateway exposes to this user. Names are the top-level folders of the gateway, case-insensitive.
    public var selectedShares: [String]?

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
        username = try c.decodeIfPresent(String.self, forKey: .username)
        selectedShares = try c.decodeIfPresent([String].self, forKey: .selectedShares)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        cloudflareClientID = try c.decodeIfPresent(String.self, forKey: .cloudflareClientID)
        cloudflareClientSecret = try c.decodeIfPresent(String.self, forKey: .cloudflareClientSecret)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        secretsModifiedAt = try c.decodeIfPresent(Date.self, forKey: .secretsModifiedAt)
    }

    // MARK: Credentials (1.5.3)

    public var cloudflare: CloudflareServiceToken? {
        guard let id = cloudflareClientID, !id.isEmpty, let secret = cloudflareClientSecret, !secret.isEmpty else { return nil }
        return CloudflareServiceToken(clientID: id, clientSecret: secret)
    }
    public var userCredentials: (username: String, password: String)? {
        guard let u = username, !u.isEmpty, let p = password else { return nil }
        return (u, p)
    }
    /// True when the profile holds everything its access mode needs to sign in.
    public var hasCredentials: Bool {
        switch accessMode {
        case .demo: return true
        case .direct: return !(apiKey ?? "").isEmpty
        case .cloudflareAccess: return !(apiKey ?? "").isEmpty && cloudflare != nil
        }
    }
    /// Sets the credentials and stamps them.
    public mutating func setCredentials(apiKey: String, cloudflare: CloudflareServiceToken?, user: (username: String, password: String)?) {
        self.apiKey = apiKey
        cloudflareClientID = cloudflare?.clientID; cloudflareClientSecret = cloudflare?.clientSecret
        username = user?.username; password = user?.password
        secretsModifiedAt = Date()
    }
    /// The same profile without any credential (servers.json in iCloud Drive, diagnostics).
    public var withoutSecrets: ServerConfig {
        var s = self; s.apiKey = nil; s.cloudflareClientID = nil; s.cloudflareClientSecret = nil; s.password = nil; s.secretsModifiedAt = nil
        return s
    }
    /// This profile with the credentials of `other` when those are newer or this one has none —
    /// copies of a profile can come from a device whose credentials are older or absent.
    public func mergingSecrets(from other: ServerConfig) -> ServerConfig {
        guard other.id == id, other.hasCredentials || other.apiKey != nil else { return self }
        let mine = secretsModifiedAt ?? .distantPast, theirs = other.secretsModifiedAt ?? .distantPast
        guard !hasCredentials || theirs > mine else { return self }
        var s = self
        s.apiKey = other.apiKey; s.cloudflareClientID = other.cloudflareClientID; s.cloudflareClientSecret = other.cloudflareClientSecret
        s.password = other.password; s.secretsModifiedAt = other.secretsModifiedAt
        if other.username != nil { s.username = other.username }
        return s
    }

    /// True when the share (a top-level gateway folder) is among the ones to show.
    public func showsShare(_ name: String) -> Bool {
        guard let selectedShares else { return true }
        let n = name.lowercased()
        return selectedShares.contains { $0.lowercased() == n }
    }

    /// True for the root and for every path inside a shown share.
    public func isVisible(path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first else { return true }
        return showsShare(String(first))
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

    /// 1.5.3: credentials move from the Keychain into the profile. For every profile without them,
    /// the Keychain items (local or iCloud Keychain, written by 1.5.2 and earlier) are copied into the
    /// profile. The Keychain items are left in place for older app versions on other devices.
    /// Returns the names of the profiles completed.
    @discardableResult
    public func migrateSecretsFromKeychain(_ keychain: KeychainStore = KeychainStore()) -> [String] {
        var list = all()
        var done: [String] = []
        for i in list.indices where !list[i].isDemo && list[i].apiKey == nil {
            guard let key = keychain.apiKey(for: list[i].id) else { continue }
            let u = keychain.userCredentials(for: list[i].id)
            list[i].apiKey = key
            if let cf = keychain.cloudflareToken(for: list[i].id) { list[i].cloudflareClientID = cf.clientID; list[i].cloudflareClientSecret = cf.clientSecret }
            if let u { list[i].username = u.username; list[i].password = u.password }
            list[i].secretsModifiedAt = list[i].modifiedAt
            done.append(list[i].name)
        }
        if !done.isEmpty {
            save(list)
            Diag.info("servers", "credentials moved from the Keychain into the profile: \(done.joined(separator: ", "))")
        }
        return done
    }
}

/// The credentials of one profile on their own: the iCloud copy under `CloudKeys.credentials`
/// (by profile id), which older app versions — that rewrite `servers.v1` without credentials — never touch.
public struct ProfileCredentials: Codable, Hashable, Sendable {
    public var apiKey: String?
    public var cloudflareClientID: String?
    public var cloudflareClientSecret: String?
    public var username: String?
    public var password: String?
    public var modifiedAt: Date?

    public init(_ s: ServerConfig) {
        apiKey = s.apiKey; cloudflareClientID = s.cloudflareClientID; cloudflareClientSecret = s.cloudflareClientSecret
        username = s.username; password = s.password; modifiedAt = s.secretsModifiedAt
    }

    /// Profiles with credentials, by id (demo excluded).
    public static func map(_ servers: [ServerConfig]) -> [String: ProfileCredentials] {
        var out: [String: ProfileCredentials] = [:]
        for s in servers where !s.isDemo && s.apiKey != nil { out[s.id] = ProfileCredentials(s) }
        return out
    }
    public static func encode(_ m: [String: ProfileCredentials]) -> Data? { try? GatewayJSON.encoder.encode(m) }
    public static func decode(_ data: Data) -> [String: ProfileCredentials] { (try? GatewayJSON.decoder.decode([String: ProfileCredentials].self, from: data)) ?? [:] }
}

public extension ServerConfig {
    /// This profile completed with `c` when those credentials are newer or the profile has none.
    func applying(_ c: ProfileCredentials) -> ServerConfig {
        var other = self
        other.apiKey = c.apiKey; other.cloudflareClientID = c.cloudflareClientID; other.cloudflareClientSecret = c.cloudflareClientSecret
        other.username = c.username ?? username; other.password = c.password; other.secretsModifiedAt = c.modifiedAt
        return mergingSecrets(from: other)
    }
}

/// Builds a ready-to-use client for a stored server from the credentials in its profile (1.5.3).
/// A profile written by an older version may still have them only in the Keychain: read there as a
/// fallback until the app migrates it. The gateway session cache stays in the Keychain (device-local).
public enum GatewayClientFactory {
    public static func client(for server: ServerConfig, keychain: KeychainStore = KeychainStore()) -> GatewayClient? {
        let p = ServerStore().server(id: server.id) ?? server
        switch p.accessMode {
        case .demo:
            return GatewayClient(baseURL: p.url, apiKey: DemoGateway.apiKey, session: DemoGateway.session())
        case .direct:
            guard let key = p.apiKey ?? keychain.apiKey(for: p.id) else { return nil }
            let u = p.userCredentials ?? keychain.userCredentials(for: p.id)
            return GatewayClient(baseURL: p.url, apiKey: key, username: u?.username, password: u?.password, sessionCache: .keychain(serverID: p.id, store: keychain))
        case .cloudflareAccess:
            guard let key = p.apiKey ?? keychain.apiKey(for: p.id), let token = p.cloudflare ?? keychain.cloudflareToken(for: p.id) else { return nil }
            let u = p.userCredentials ?? keychain.userCredentials(for: p.id)
            return GatewayClient(baseURL: p.url, apiKey: key, username: u?.username, password: u?.password, extraHeaders: token.headers, sessionCache: .keychain(serverID: p.id, store: keychain))
        }
    }
}
