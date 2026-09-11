import Foundation
import CryptoKit

/// Pairing an Apple TV without typing on the remote: the TV shows a 6-digit code, the phone/Mac
/// encrypts the server and its secrets with a key derived from that code and drops the blob in the
/// iCloud Key-Value Store under `tv.pair.<code>`; the TV picks it up, decrypts, stores and deletes it.
/// AES-GCM; the code never leaves the two screens, so iCloud only ever sees ciphertext.
public struct PairingPayload: Codable, Sendable {
    public var server: ServerConfig
    public var apiKey: String
    public var cloudflareClientID: String?
    public var cloudflareClientSecret: String?
    public var username: String?
    public var password: String?
    public init(server: ServerConfig, apiKey: String, cloudflare: CloudflareServiceToken?, username: String?, password: String?) {
        self.server = server; self.apiKey = apiKey
        cloudflareClientID = cloudflare?.clientID; cloudflareClientSecret = cloudflare?.clientSecret
        self.username = username; self.password = password
    }
    public var cloudflare: CloudflareServiceToken? {
        guard let id = cloudflareClientID, let secret = cloudflareClientSecret else { return nil }
        return CloudflareServiceToken(clientID: id, clientSecret: secret)
    }
}

public enum TVPairing {
    public static let ttl: TimeInterval = 15 * 60

    public static func generateCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }
    public static func kvsKey(_ code: String) -> String { "tv.pair." + code }

    static func key(_ code: String) -> SymmetricKey {
        // Deliberately slow derivation (a 6-digit code is small): 20 000 chained SHA-256 rounds.
        var d = Data(("unraid-drive-tv-pairing:" + code).utf8)
        for _ in 0..<20_000 { d = Data(SHA256.hash(data: d)) }
        return SymmetricKey(data: d)
    }

    public static func encrypt(_ payload: PairingPayload, code: String) throws -> Data {
        let plain = try GatewayJSON.encoder.encode(payload)
        let box = try AES.GCM.seal(plain, using: key(code))
        guard let combined = box.combined else { throw GatewayError.decoding("pairing: cannot seal") }
        return combined
    }

    public static func decrypt(_ data: Data, code: String) throws -> PairingPayload {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key(code))
        return try GatewayJSON.decoder.decode(PairingPayload.self, from: plain)
    }
}
