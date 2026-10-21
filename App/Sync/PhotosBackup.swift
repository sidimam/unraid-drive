import Foundation
import Photos
import UnraidGatewayKit

/// Backs the device's Photos library up to an Unraid folder through the gateway: originals
/// (RAW/JPEG/HEIC/video, both halves of a Live Photo), incremental by asset id + modification date,
/// laid out as `<remote>/<YYYY>/<YYYY-MM>/<original file name>`, plus an `albums.json` manifest
/// (album name → file names). Never deletes anything on Unraid.
actor PhotosBackup {
    private let client: GatewayClient
    private let pair: SyncPair
    private let onProgress: (@Sendable (SyncEngine.Progress) -> Void)?
    /// Stop after this many assets (background tasks have a time budget); the next run continues.
    private let limit: Int
    private var cancelled = false

    init(client: GatewayClient, pair: SyncPair, limit: Int = 400, onProgress: (@Sendable (SyncEngine.Progress) -> Void)? = nil) {
        self.client = client; self.pair = pair; self.limit = limit; self.onProgress = onProgress
    }

    func cancel() { cancelled = true }

    static func authorize() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited: return true
        case .notDetermined:
            let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return s == .authorized || s == .limited
        default: return false
        }
    }

    func run(trigger: String) async -> (SyncRunSummary, [SyncFileRecord]) {
        let started = Date()
        var summary = SyncRunSummary(trigger: trigger)
        var records: [SyncFileRecord] = []
        defer { summary.durationMs = Int64(Date().timeIntervalSince(started) * 1000) }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            summary.status = .failed; summary.error = String(localized: "Photos access is not allowed: enable it in Settings › Privacy › Photos.")
            return (summary, records)
        }
        do { _ = try await client.stat(pair.remotePath) } catch GatewayError.notFound {
            do { _ = try await client.mkdir(pair.remotePath, parents: true) } catch { summary.status = .failed; summary.error = error.localizedDescription; return (summary, records) }
        } catch { summary.status = .failed; summary.error = error.localizedDescription; return (summary, records) }

        var state = SyncStore.state(pair.id)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: options)
        var pending: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in
            let key = a.localIdentifier
            let stamp = Self.stamp(a)
            if state.assets[key] != stamp { pending.append(a) }
        }
        let total = min(pending.count, limit)
        onProgress?(.init(phase: "syncing", done: 0, total: total, current: nil, bytes: 0))
        var bytes: Int64 = 0
        var done = 0
        let df = DateFormatter(); df.dateFormat = "yyyy"
        let mf = DateFormatter(); mf.dateFormat = "yyyy-MM"
        for a in pending.prefix(limit) {
            if cancelled { summary.status = .partial; summary.error = "cancelled"; break }
            let date = a.creationDate ?? a.modificationDate ?? Date()
            let folder = pair.remotePath + "/" + df.string(from: date) + "/" + mf.string(from: date)
            let resources = Self.resourcesToBackUp(a)
            var ok = true
            for res in resources {
                let name = Self.fileName(res, asset: a)
                let remotePath = folder + "/" + name
                onProgress?(.init(phase: "syncing", done: done, total: total, current: name, bytes: bytes))
                do {
                    // Already there with the same size? Then it was uploaded by an earlier installation.
                    if let existing = try? await client.stat(remotePath), existing.size > 0, let size = Self.resourceSize(res), existing.size == size {
                        continue
                    }
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("photos-\(UUID().uuidString)-\(name)")
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    try await Self.write(res, to: tmp)
                    _ = try await client.mkdir(folder, parents: true)
                    let (_, size) = SyncEngine.attrs(tmp)
                    _ = try await client.upload(fileURL: tmp, to: remotePath, overwrite: true, mtime: a.modificationDate ?? date)
                    bytes += size; summary.files += 1
                    records.append(.init(path: remotePath, direction: .up, bytes: size))
                    ActivityLog.append(ActivityEvent(serverID: pair.serverID, path: remotePath, kind: .upload, bytes: size))
                } catch {
                    ok = false; summary.errors += 1
                    records.append(.init(path: remotePath, direction: .up, outcome: .failed, detail: error.localizedDescription))
                    Diag.error("photos", name, error)
                }
            }
            if ok { state.assets[a.localIdentifier] = Self.stamp(a) }
            done += 1
            if done % 10 == 0 { SyncStore.saveState(pair.id, state) }
        }
        SyncStore.saveState(pair.id, state)
        // Albums manifest (user albums only), cheap and always refreshed.
        if !cancelled {
            do {
                let manifest = Self.albumsManifest()
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("albums-\(UUID().uuidString).json")
                try manifest.write(to: tmp)
                _ = try await client.upload(fileURL: tmp, to: pair.remotePath + "/albums.json", overwrite: true)
                try? FileManager.default.removeItem(at: tmp)
            } catch { Diag.error("photos", "albums.json", error) }
        }
        summary.bytes = bytes
        if summary.status != .partial {
            if pending.count > limit { summary.status = summary.errors > 0 ? .partial : .ok; summary.error = String(localized: "\(pending.count - limit) more to back up: continues at the next run.") }
            else { summary.status = summary.errors > 0 ? (summary.files > 0 ? .partial : .failed) : .ok }
        }
        if summary.errors > 0, summary.error == nil { summary.error = records.first { $0.outcome == .failed }?.detail }
        onProgress?(.init(phase: "done", done: total, total: total, current: nil, bytes: bytes))
        Diag.info("photos", "\(pair.remotePath): \(summary.status.rawValue), \(summary.files) files, \(bytes) bytes, \(summary.errors) errors, \(pending.count) pending before, \(trigger)")
        return (summary, records)
    }

    // MARK: helpers

    nonisolated static func stamp(_ a: PHAsset) -> String {
        "\(Int(a.modificationDate?.timeIntervalSince1970 ?? 0))|\(PHAssetResource.assetResources(for: a).count)"
    }

    nonisolated static func resourcesToBackUp(_ a: PHAsset) -> [PHAssetResource] {
        let all = PHAssetResource.assetResources(for: a)
        // Originals only: the full-size photo/video, the RAW half and the Live Photo video.
        let wanted: Set<PHAssetResourceType> = [.photo, .video, .alternatePhoto, .fullSizePhoto, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo]
        var out = all.filter { wanted.contains($0.type) }
        // Prefer the full-size over the adjusted when both exist for the same role.
        if out.contains(where: { $0.type == .fullSizePhoto }) { out.removeAll { $0.type == .photo } }
        if out.contains(where: { $0.type == .fullSizeVideo }) { out.removeAll { $0.type == .video } }
        if out.contains(where: { $0.type == .fullSizePairedVideo }) { out.removeAll { $0.type == .pairedVideo } }
        return out.isEmpty ? all.prefix(1).map { $0 } : out
    }

    nonisolated static func fileName(_ r: PHAssetResource, asset a: PHAsset) -> String {
        var name = r.originalFilename
        if name.isEmpty { name = a.localIdentifier.replacingOccurrences(of: "/", with: "-") }
        // Live Photo halves share the stem: keep them apart by extension; the paired video keeps its own name.
        return name
    }

    nonisolated static func resourceSize(_ r: PHAssetResource) -> Int64? {
        (r.value(forKey: "fileSize") as? Int64)
    }

    nonisolated static func write(_ r: PHAssetResource, to url: URL) async throws {
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true   // iCloud-optimised originals are fetched on demand
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: r, toFile: url, options: opts) { err in
                if let err { c.resume(throwing: err) } else { c.resume() }
            }
        }
    }

    nonisolated static func albumsManifest() -> Data {
        var albums: [String: [String]] = [:]
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        collections.enumerateObjects { col, _, _ in
            let title = col.localizedTitle ?? col.localIdentifier
            var names: [String] = []
            PHAsset.fetchAssets(in: col, options: nil).enumerateObjects { a, _, _ in
                if let r = PHAssetResource.assetResources(for: a).first { names.append(r.originalFilename) }
            }
            albums[title] = names
        }
        let payload: [String: Any] = ["generatedAt": ISO8601DateFormatter().string(from: Date()), "albums": albums]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }
}
