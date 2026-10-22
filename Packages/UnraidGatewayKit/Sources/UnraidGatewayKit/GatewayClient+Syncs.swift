import Foundation

/// `/api/v1/syncs` of unraid-gateway 0.14: the gateway keeps a copy of every pair this device runs,
/// can pause it (web UI / console) and records each run with the files that moved.
public extension GatewayClient {
    /// The pairs the gateway knows for this device.
    func remoteSyncs() async throws -> [RemoteSync] {
        let (data, _) = try await authorized(get("/api/v1/syncs", []))
        struct R: Decodable { var syncs: [RemoteSync] }
        return try decode(R.self, data).syncs
    }

    /// Creates or updates the gateway's copy of a pair. Returns the stored copy (whose `enabled` /
    /// `disabledBy` tell whether the web UI paused it).
    @discardableResult
    func putSync(_ pair: SyncPair) async throws -> RemoteSync {
        var req = get("/api/v1/syncs/" + pair.id, [])
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "kind": pair.kind.rawValue, "localLabel": pair.localLabel, "remotePath": pair.remotePath,
            "mode": pair.mode.rawValue, "enabled": pair.enabled,
            "conflicts": pair.conflicts.rawValue, "hashCheck": pair.hashCheck,
        ])
        let (data, _) = try await authorized(req)
        return try decode(RemoteSync.self, data)
    }

    /// Pauses or resumes the pair on the gateway (the app itself: no "paused by" is recorded).
    @discardableResult
    func setSyncEnabled(_ id: String, _ enabled: Bool) async throws -> RemoteSync {
        var req = get("/api/v1/syncs/" + id, [])
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
        let (data, _) = try await authorized(req)
        return try decode(RemoteSync.self, data)
    }

    func deleteSync(_ id: String) async throws {
        var req = get("/api/v1/syncs/" + id, [])
        req.httpMethod = "DELETE"
        _ = try await authorized(req)
    }

    /// Reports one run. Throws `GatewayError.conflict("sync_disabled")` when the gateway paused the pair.
    @discardableResult
    func reportSyncRun(_ id: String, _ run: SyncRunSummary, files: [SyncFileRecord]) async throws -> RemoteSync {
        var req = get("/api/v1/syncs/" + id + "/runs", [])
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { var run: SyncRunSummary; var files: [SyncFileRecord] }
        req.httpBody = try GatewayJSON.encoder.encode(Body(run: run, files: Array(files.prefix(100))))
        let (data, _) = try await authorized(req)
        return try decode(RemoteSync.self, data)
    }
}
