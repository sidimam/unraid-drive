import Foundation
import CryptoKit

/// A content fingerprint as `GET /api/v1/fs/hash` returns it (gateway 0.16+).
public struct FileFingerprint: Codable, Sendable {
    public var path: String
    public var size: Int64
    public var etag: String?
    public var algo: String
    public var quick: Bool
    public var hash: String
}

/// The same fingerprint computed locally, byte for byte like the gateway: md5 of the whole file up to
/// 2 MiB, otherwise md5 of the first MiB + the last MiB + the decimal size. Cheap on a 4 GB video.
public enum QuickFingerprint {
    public static let window = 1 << 20

    public static func md5(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        var md5 = Insecure.MD5()
        if size <= Int64(2 * window) {
            while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { md5.update(data: chunk) }
        } else {
            md5.update(data: try h.read(upToCount: window) ?? Data())
            try h.seek(toOffset: UInt64(size) - UInt64(window))
            md5.update(data: try h.read(upToCount: window) ?? Data())
            md5.update(data: Data(String(size).utf8))
        }
        return md5.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// What a `GatewayClient` keeps between processes so that a relaunched File Provider extension does
/// not sign in again at every request (1.5.1): the token, the user and the share permissions.
public struct CachedSession: Codable, Sendable {
    public var token: String
    public var user: String?
    public var shares: [String: ShareAccess]?
    /// SHA-256 of the API key the session was opened with: a rotated key invalidates the cache.
    public var apiKeyHash: String
    public init(token: String, user: String?, shares: [String: ShareAccess]?, apiKeyHash: String) { self.token = token; self.user = user; self.shares = shares; self.apiKeyHash = apiKeyHash }
}

/// Storage for a `CachedSession`; the keychain-backed one lives in `KeychainStore`.
public struct SessionCache: Sendable {
    public let load: @Sendable () -> CachedSession?
    public let save: @Sendable (CachedSession) -> Void
    public let clear: @Sendable () -> Void
    public init(load: @escaping @Sendable () -> CachedSession?, save: @escaping @Sendable (CachedSession) -> Void, clear: @escaping @Sendable () -> Void) { self.load = load; self.save = save; self.clear = clear }

    public static func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Keychain-backed cache for one stored server (app and extension share the access group).
    public static func keychain(serverID: String, store: KeychainStore = KeychainStore()) -> SessionCache {
        SessionCache(load: { store.session(for: serverID) }, save: { store.set(session: $0, for: serverID) }, clear: { store.removeSession(for: serverID) })
    }
}
