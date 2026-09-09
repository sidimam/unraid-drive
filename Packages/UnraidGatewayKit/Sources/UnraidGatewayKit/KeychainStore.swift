import Foundation
import Security

/// A Cloudflare Zero Trust service token.
public struct CloudflareServiceToken: Hashable, Sendable {
    public var clientID: String
    public var clientSecret: String
    public init(clientID: String, clientSecret: String) { self.clientID = clientID; self.clientSecret = clientSecret }
    public var headers: [String: String] {
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline } }
        return ["CF-Access-Client-Id": clean(clientID), "CF-Access-Client-Secret": clean(clientSecret)]
    }

    /// Cloudflare's dashboard copies tokens as header lines, e.g.
    /// `CF-Access-Client-Id: 8297….access`. Accept a raw value, a labelled line, or both
    /// lines pasted together, and return what was recognised.
    public static func parse(_ text: String) -> (clientID: String?, clientSecret: String?) {
        var id: String?, secret: String?
        var loose: [String] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if let r = lower.range(of: "cf-access-client-id") {
                id = String(line[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ": \t\"'"))
            } else if let r = lower.range(of: "cf-access-client-secret") {
                secret = String(line[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ": \t\"'"))
            } else {
                loose.append(line)
            }
        }
        for v in loose {
            if v.hasSuffix(".access") { id = id ?? v } else if secret == nil, v.count >= 32 { secret = v } else { id = id ?? v }
        }
        return (id, secret)
    }
}

/// Stores per-server secrets in the shared Keychain access group so the
/// File Provider extension can authenticate without the app running.
///
/// Items can be stored as *synchronizable*: iCloud Keychain then carries them
/// (end-to-end encrypted) to the user's other devices and to a restored
/// device. Reads always look for both variants.
public struct KeychainStore: Sendable {
    private let service = "com.sdimambro.unraid-drive.secrets"
    public init() {}

    // MARK: API key
    public func set(apiKey: String, for serverID: String, synchronizable: Bool = false) throws {
        try set(apiKey, account: serverID, synchronizable: synchronizable)
    }
    public func apiKey(for serverID: String) -> String? { get(account: serverID) }

    // MARK: Cloudflare Access service token
    public func set(cloudflareToken t: CloudflareServiceToken, for serverID: String, synchronizable: Bool = false) throws {
        try set(t.clientID, account: serverID + ".cf-id", synchronizable: synchronizable)
        try set(t.clientSecret, account: serverID + ".cf-secret", synchronizable: synchronizable)
    }
    public func cloudflareToken(for serverID: String) -> CloudflareServiceToken? {
        guard let id = get(account: serverID + ".cf-id"), let secret = get(account: serverID + ".cf-secret") else { return nil }
        return CloudflareServiceToken(clientID: id, clientSecret: secret)
    }

    // MARK: Unraid user credentials
    public func set(username: String, password: String, for serverID: String, synchronizable: Bool = false) throws {
        try set(username, account: serverID + ".user", synchronizable: synchronizable)
        try set(password, account: serverID + ".pass", synchronizable: synchronizable)
    }
    public func userCredentials(for serverID: String) -> (username: String, password: String)? {
        guard let u = get(account: serverID + ".user"), let p = get(account: serverID + ".pass"), !u.isEmpty else { return nil }
        return (u, p)
    }
    public func removeUserCredentials(for serverID: String) {
        for acct in [serverID + ".user", serverID + ".pass"] {
            for sync in [false, true] { SecItemDelete(query(acct, synchronizable: sync) as CFDictionary) }
        }
    }

    public func remove(for serverID: String) {
        for acct in accounts(serverID) {
            for sync in [false, true] { SecItemDelete(query(acct, synchronizable: sync) as CFDictionary) }
        }
    }

    /// Re-stores every secret of a server with the requested synchronizable flag
    /// (used when the user turns iCloud sync on or off).
    public func setSynchronizable(_ synchronizable: Bool, for serverID: String) throws {
        let key = apiKey(for: serverID)
        let token = cloudflareToken(for: serverID)
        let user = userCredentials(for: serverID)
        remove(for: serverID)
        if let key { try set(apiKey: key, for: serverID, synchronizable: synchronizable) }
        if let token { try set(cloudflareToken: token, for: serverID, synchronizable: synchronizable) }
        if let user { try set(username: user.username, password: user.password, for: serverID, synchronizable: synchronizable) }
    }

    // MARK: Plumbing

    private func accounts(_ serverID: String) -> [String] { [serverID, serverID + ".cf-id", serverID + ".cf-secret", serverID + ".user", serverID + ".pass"] }

    private func query(_ account: String, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.identifier,
            kSecAttrSynchronizable as String: synchronizable,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func set(_ value: String, account: String, synchronizable: Bool) throws {
        let data = Data(value.utf8)
        // One variant at a time: drop the other so reads are unambiguous.
        SecItemDelete(query(account, synchronizable: !synchronizable) as CFDictionary)
        var q = query(account, synchronizable: synchronizable)
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            let s = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        } else {
            q[kSecValueData as String] = data
            // Synchronizable items cannot be "ThisDeviceOnly".
            q[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let s = SecItemAdd(q as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        }
    }

    private func get(account: String) -> String? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.identifier,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { q.removeAll(); return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
