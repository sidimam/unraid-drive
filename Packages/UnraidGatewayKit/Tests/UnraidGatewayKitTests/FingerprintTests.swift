import XCTest
import CryptoKit
@testable import UnraidGatewayKit

/// The local fingerprint must match the gateway's `Fingerprint()` byte for byte (internal/fsapi/hash.go).
final class FingerprintTests: XCTestCase {
    private func tmp(_ data: Data) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: u); return u
    }
    func testSmallFileIsHashedWhole() throws {
        let u = try tmp(Data("hello".utf8))
        XCTAssertEqual(try QuickFingerprint.md5(of: u), "5d41402abc4b2a76b9719d911017c592")
    }
    func testBigFileUsesHeadTailAndSize() throws {
        let w = QuickFingerprint.window
        let big = Data(repeating: 7, count: 3 * w)
        let u = try tmp(big)
        var md5 = Insecure.MD5()
        md5.update(data: big.prefix(w)); md5.update(data: big.suffix(w)); md5.update(data: Data("3145728".utf8))
        let want = md5.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try QuickFingerprint.md5(of: u), want)
        XCTAssertNotEqual(try QuickFingerprint.md5(of: u), Insecure.MD5.hash(data: big).map { String(format: "%02x", $0) }.joined())
    }
    func testSyncPairDecodesWithoutHashCheck() throws {
        let json = """
        {"id":"x","serverID":"s","kind":"downloads","localLabel":"Downloads","remotePath":"/documents/dl","mode":"up","conflicts":"newest","deletions":"keep","schedule":"continuous","excludes":[],"wifiOnly":false,"enabled":true,"createdAt":0}
        """
        let p = try JSONDecoder().decode(SyncPair.self, from: Data(json.utf8))
        XCTAssertTrue(p.hashCheck)
        XCTAssertEqual(p.conflicts, .newest)
    }
}
