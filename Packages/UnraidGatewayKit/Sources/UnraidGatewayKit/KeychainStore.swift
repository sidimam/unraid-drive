import Foundation
import Security

/// A Cloudflare Zero Trust service token.
public struct CloudflareServiceToken: Hashable, Sendable {
    public var clientID: String
    public var clientSecret: String
    public init(clientID: String, clientSecret: String) { self.clientID = clientID; self.clientSecret = clientSecret }

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
        // Unlabelled values: the id ends with ".access", the secret is a 64-hex string.
        for v in loose {
            if v.hasSuffix(".access") { id = id ?? v } else if secret == nil, v.count >= 32 { secret = v } else { id = id ?? v }
        }
        return (id, secret)
    }
    public var headers: [String: String] {
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline } }
        return ["CF-Access-Client-Id": clean(clientID), "CF-Access-Client-Secret": clean(clientSecret)]
    }
}

/// Stores per-server secrets in the shared Keychain access group so the
/// File Provider extension can authenticate without the app running.
public struct KeychainStore: Sendable {
    private let service = "com.sdimambro.unraid-drive.secrets"
    public init() {}

    // MARK: API key
    public func set(apiKey: String, for serverID: String) throws { try set(apiKey, account: serverID) }
    public func apiKey(for serverID: String) -> String? { get(account: serverID) }

    // MARK: Cloudflare Access service token
    public func set(cloudflareToken t: CloudflareServiceToken, for serverID: String) throws {
        try set(t.clientID, account: serverID + ".cf-id")
        try set(t.clientSecret, account: serverID + ".cf-secret")
    }
    public func cloudflareToken(for serverID: String) -> CloudflareServiceToken? {
        guard let id = get(account: serverID + ".cf-id"), let secret = get(account: serverID + ".cf-secret") else { return nil }
        return CloudflareServiceToken(clientID: id, clientSecret: secret)
    }

    public func remove(for serverID: String) {
        for acct in [serverID, serverID + ".cf-id", serverID + ".cf-secret"] {
            SecItemDelete(query(acct) as CFDictionary)
        }
    }

    // MARK: Plumbing

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.identifier,
        ]
    }

    private func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var q = query(account)
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            let s = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        } else {
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let s = SecItemAdd(q as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        }
    }

    private func get(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
