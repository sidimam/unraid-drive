import XCTest
@testable import UnraidGatewayKit

/// 1.5.3: the credentials travel with the profile. These cover the merges that decide which copy
/// wins when the same profile comes back from iCloud (another device, an older app version, a reinstall).
final class ProfileCredentialsTests: XCTestCase {
    private func profile(key: String? = nil, at: Date? = nil) -> ServerConfig {
        var s = ServerConfig(id: "P1", name: "Tower", url: URL(string: "https://unraid.example")!, accessMode: .cloudflareAccess)
        if let key { s.setCredentials(apiKey: key, cloudflare: .init(clientID: "id.access", clientSecret: "sec-" + key), user: ("simone", "pw-" + key)); s.secretsModifiedAt = at }
        return s
    }

    func testRoundTripKeepsCredentialsAndOldJSONDecodes() throws {
        let s = profile(key: "K1", at: Date(timeIntervalSince1970: 100))
        let back = ServerStore.decode(ServerStore.encode([s])!)
        XCTAssertEqual(back.first?.apiKey, "K1")
        XCTAssertEqual(back.first?.cloudflare?.clientSecret, "sec-K1")
        XCTAssertEqual(back.first?.userCredentials?.password, "pw-K1")
        XCTAssertTrue(back.first!.hasCredentials)
        // A 1.5.2 profile (no credential fields) still decodes, without credentials.
        let old = #"[{"id":"P1","name":"Tower","url":"https://unraid.example","createdAt":"2026-01-01T00:00:00Z","accessMode":"direct","modifiedAt":"2026-01-01T00:00:00Z"}]"#
        let o = ServerStore.decode(Data(old.utf8))
        XCTAssertEqual(o.count, 1); XCTAssertNil(o[0].apiKey); XCTAssertFalse(o[0].hasCredentials)
    }

    func testWithoutSecretsStripsEverythingButTheUserName() {
        let s = profile(key: "K1").withoutSecrets
        XCTAssertNil(s.apiKey); XCTAssertNil(s.cloudflareClientSecret); XCTAssertNil(s.password)
        XCTAssertEqual(s.username, "simone")
        let json = String(data: ServerStore.encode([s])!, encoding: .utf8)!
        XCTAssertFalse(json.contains("K1")); XCTAssertFalse(json.contains("sec-")); XCTAssertFalse(json.contains("pw-"))
    }

    func testMergeKeepsCredentialsWhenTheOtherCopyHasNone() {
        // An older app version pushed the profile without credentials (newer modifiedAt): the local
        // credentials must survive.
        let mine = profile(key: "K1", at: Date(timeIntervalSince1970: 100))
        var stripped = mine.withoutSecrets; stripped.modifiedAt = Date(timeIntervalSince1970: 500)
        XCTAssertEqual(stripped.mergingSecrets(from: mine).apiKey, "K1")
        XCTAssertEqual(mine.mergingSecrets(from: stripped).apiKey, "K1")
    }

    func testMergeTakesNewerCredentials() {
        let old = profile(key: "OLD", at: Date(timeIntervalSince1970: 100))
        let new = profile(key: "NEW", at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(old.mergingSecrets(from: new).apiKey, "NEW")
        XCTAssertEqual(new.mergingSecrets(from: old).apiKey, "NEW")
        XCTAssertEqual(old.mergingSecrets(from: new).password, "pw-NEW")
    }

    func testCredentialsMapCompletesAStrippedProfile() {
        // Fresh install: servers.json (no credentials) + the credentials.v1 map → a complete profile.
        let full = profile(key: "K1", at: Date(timeIntervalSince1970: 100))
        let map = ProfileCredentials.decode(ProfileCredentials.encode(ProfileCredentials.map([full, .demo]))!)
        XCTAssertEqual(map.count, 1)
        let restored = full.withoutSecrets.applying(map["P1"]!)
        XCTAssertTrue(restored.hasCredentials)
        XCTAssertEqual(restored.cloudflare?.headers["CF-Access-Client-Secret"], "sec-K1")
    }

    func testFactoryUsesTheProfileCredentials() {
        var s = profile(key: "K1"); s.accessMode = .direct
        XCTAssertNotNil(GatewayClientFactory.client(for: s, keychain: KeychainStore()))
        var cf = profile(key: "K1"); cf.cloudflareClientSecret = nil
        XCTAssertFalse(cf.hasCredentials)
    }
}
