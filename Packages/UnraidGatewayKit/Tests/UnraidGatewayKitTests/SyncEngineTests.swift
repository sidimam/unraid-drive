import XCTest
@testable import UnraidGatewayKit

/// Integration test of the sync engine against a running gateway (scripts/localtest.sh of
/// unraid-gateway). Skipped unless GW_TEST_URL and GW_TEST_KEY are set:
///   GW_TEST_URL=http://127.0.0.1:8585 GW_TEST_KEY=… swift test --filter SyncEngineTests
final class SyncEngineTests: XCTestCase {
    var client: GatewayClient!
    var local: URL!
    var remote: String!

    override func setUp() async throws {
        guard let url = ProcessInfo.processInfo.environment["GW_TEST_URL"].flatMap(URL.init), let key = ProcessInfo.processInfo.environment["GW_TEST_KEY"] else {
            throw XCTSkip("set GW_TEST_URL and GW_TEST_KEY to run against a gateway")
        }
        SyncStore.overrideDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("syncstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: SyncStore.overrideDirectory!, withIntermediateDirectories: true)
        client = GatewayClient(baseURL: url, apiKey: key)
        _ = try await client.login(register: true)
        local = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        remote = "/testshare/synctest-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() async throws {
        if let local { try? FileManager.default.removeItem(at: local) }
        if let client, let remote { try? await client.delete(remote, recursive: true) }
    }

    private func pair(mode: SyncMode, conflicts: ConflictPolicy = .newest, deletions: DeletionPolicy = .keep) throws -> SyncPair {
        var p = SyncPair(serverID: "test", kind: .folder, localLabel: local.path, localBookmark: try SyncPair.bookmark(for: local), remotePath: remote, mode: mode, conflicts: conflicts, deletions: deletions)
        p.id = "test-" + UUID().uuidString
        return p
    }

    private func write(_ rel: String, _ text: String, mtime: Date? = nil) throws {
        let u = local.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
        if let mtime { try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: u.path) }
    }

    private func remoteText(_ rel: String) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = try await client.download(remote + "/" + rel, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try String(contentsOf: tmp, encoding: .utf8)
    }

    /// Two devices of the same user sync into the same Unraid folder: the second one finds the file
    /// already there with another date — same bytes → recorded as in sync, nothing moved, no conflict (1.5.1).
    func testIdenticalFileFromAnotherDeviceIsSkipped() async throws {
        let p = try pair(mode: .up, conflicts: .ask)
        let up = FileManager.default.temporaryDirectory.appendingPathComponent("other-device-\(UUID().uuidString)")
        try "SAME BYTES".write(to: up, atomically: true, encoding: .utf8)
        _ = try await client.mkdir(remote, parents: true)
        _ = try await client.upload(fileURL: up, to: remote + "/photo.jpg", mtime: Date().addingTimeInterval(-86400))
        try write("photo.jpg", "SAME BYTES", mtime: Date())
        var (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.conflicts, 0, "identical content must not be a conflict")
        XCTAssertEqual(run.files, 0); XCTAssertTrue(files.isEmpty)
        // A real difference with the same size on BOTH sides follows the policy (ask → recorded as a conflict);
        // a change on this device alone is just an upload, as before.
        try "SAME BYTEZ".write(to: up, atomically: true, encoding: .utf8)
        _ = try await client.upload(fileURL: up, to: remote + "/photo.jpg", mtime: Date().addingTimeInterval(30))
        try write("photo.jpg", "SAME BYTEX", mtime: Date().addingTimeInterval(60))
        (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.conflicts, 1)
        // "This device wins" pushes it.
        var q = p; q.conflicts = .overwrite
        (run, files) = await SyncEngine(client: client, pair: q, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.errors, 0, run.error ?? "")
        let r = try await remoteText("photo.jpg"); XCTAssertEqual(r, "SAME BYTEX")
    }

    func testUploadDownloadDeleteAndConflicts() async throws {
        let p = try pair(mode: .both, conflicts: .newest, deletions: .mirror)
        try write("a.txt", "A1")
        try write("sub/b.txt", "B1")
        try write(".DS_Store", "junk")
        // 1. First run: everything goes up.
        var (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.status, .ok, run.error ?? "")
        XCTAssertEqual(run.files, 2)
        let r_2350 = try await remoteText("a.txt"); XCTAssertEqual(r_2350, "A1")
        let r_4302 = try await remoteText("sub/b.txt"); XCTAssertEqual(r_4302, "B1")
        XCTAssertFalse(files.contains { $0.path.hasSuffix(".DS_Store") })
        // 2. Nothing changed: no-op.
        (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.files, 0); XCTAssertEqual(run.errors, 0)
        // 3. A new file appears on Unraid and one is deleted there: download + mirror deletion.
        let up = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "C1".write(to: up, atomically: true, encoding: .utf8)
        _ = try await client.upload(fileURL: up, to: remote + "/c.txt")
        try await client.delete(remote + "/sub/b.txt", recursive: false)
        (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.errors, 0, run.error ?? "")
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("c.txt"), encoding: .utf8), "C1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("sub/b.txt").path))
        // 4. Conflict: both sides change a.txt; the newest (local, written later) wins.
        try "A-remote".write(to: up, atomically: true, encoding: .utf8)
        _ = try await client.upload(fileURL: up, to: remote + "/a.txt", mtime: Date().addingTimeInterval(-3600))
        try write("a.txt", "A-local", mtime: Date())
        (run, files) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.conflicts, 1)
        let r_4937 = try await remoteText("a.txt"); XCTAssertEqual(r_4937, "A-local")
        // 5. Keep both: the local copy is renamed, the Unraid copy takes the original name.
        let kb = try pair(mode: .both, conflicts: .keepBoth)
        SyncStore.saveState(kb.id, SyncStore.state(p.id))
        try "A-remote-2".write(to: up, atomically: true, encoding: .utf8)
        _ = try await client.upload(fileURL: up, to: remote + "/a.txt", mtime: Date())
        try write("a.txt", "A-local-2", mtime: Date().addingTimeInterval(1))
        (run, files) = await SyncEngine(client: client, pair: kb, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.conflicts, 1, run.error ?? "")
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("a.txt"), encoding: .utf8), "A-remote-2")
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("a (Test).txt"), encoding: .utf8), "A-local-2")
        let r_7034 = try await remoteText("a (Test).txt"); XCTAssertEqual(r_7034, "A-local-2")
        SyncStore.removeAll(for: "test")
    }

    func testUpOnlyNeverDeletesLocally() async throws {
        let p = try pair(mode: .up, deletions: .mirror)
        try write("x.txt", "X")
        var (run, _) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        XCTAssertEqual(run.status, .ok, run.error ?? "")
        try await client.delete(remote + "/x.txt", recursive: false)
        (run, _) = await SyncEngine(client: client, pair: p, deviceTag: "Test").run(trigger: "manual")
        // Up-only: the file deleted on Unraid is uploaded again, the local copy is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent("x.txt").path))
        let r_9536 = try await remoteText("x.txt"); XCTAssertEqual(r_9536, "X")
        SyncStore.removeAll(for: "test")
    }
}
