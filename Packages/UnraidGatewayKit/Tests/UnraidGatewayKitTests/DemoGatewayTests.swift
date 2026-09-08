import XCTest
@testable import UnraidGatewayKit

final class DemoGatewayTests: XCTestCase {
    func testDemoRoundTrip() async throws {
        let client = GatewayClientFactory.client(for: .demo)!
        let login = try await client.login()
        XCTAssertEqual(login.identity.name, "demo")
        let root = try await client.list("/")
        XCTAssertEqual(root.entries.map(\.name), ["documents", "downloads", "media"])
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        let up = try await client.upload(fileURL: tmp, to: "/documents/hello.txt")
        XCTAssertEqual(up.size, 5)
        let moved = try await client.move("/documents/hello.txt", to: "/documents/Notes/hello.txt")
        XCTAssertEqual(moved.path, "/documents/Notes/hello.txt")
        let dl = FileManager.default.temporaryDirectory.appendingPathComponent("demo-dl-\(UUID().uuidString).txt")
        _ = try await client.download("/documents/Notes/hello.txt", to: dl)
        XCTAssertEqual(try String(contentsOf: dl, encoding: .utf8), "hello")
        let changes = try await client.changes("/documents", since: 0)
        XCTAssertTrue(changes.files.contains { $0.path == "/documents/Notes/hello.txt" })
        try await client.delete("/documents/Notes/hello.txt")
        do { _ = try await client.stat("/documents/Notes/hello.txt"); XCTFail("should be gone") } catch GatewayError.notFound {}
        do { try await client.delete("/documents"); XCTFail("share root must be protected") } catch GatewayError.forbidden {}
        let dash = try await client.graphQL(Dashboard.query, as: Dashboard.self)
        XCTAssertEqual(dash.info?.os?.hostname, "demo-nas")
    }

    func testResumableUploadThroughDemo() async throws {
        let client = GatewayClientFactory.client(for: .demo)!
        await client.setResumableThreshold(1024)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).bin")
        let payload = Data((0..<(3 * 1024 + 17)).map { UInt8($0 % 251) })
        try payload.write(to: tmp)
        await client.setChunkSize(1024)
        let e = try await client.upload(fileURL: tmp, to: "/downloads/big.bin")
        XCTAssertEqual(e.size, Int64(payload.count))
        let dl = FileManager.default.temporaryDirectory.appendingPathComponent("big-dl-\(UUID().uuidString).bin")
        _ = try await client.download("/downloads/big.bin", to: dl)
        XCTAssertEqual(try Data(contentsOf: dl), payload)
        try await client.delete("/downloads/big.bin")
    }
}
