import Foundation

/// Runs one folder pair (local folder ↔ Unraid folder) through the gateway: three-way comparison
/// between the local tree, the remote tree and the state recorded at the last run, then uploads,
/// downloads, deletions and conflict handling according to the pair's mode and policies.
/// Nothing Unraid → Unraid ever passes through the device; the engine only moves what differs.
public actor SyncEngine {
    public struct Progress: Sendable {
        public var phase: String        // "scanning", "syncing", "done"
        public var done: Int
        public var total: Int
        public var current: String?
        public var bytes: Int64
        public init(phase: String, done: Int, total: Int, current: String?, bytes: Int64) { self.phase = phase; self.done = done; self.total = total; self.current = current; self.bytes = bytes }
    }

    public enum Failure: Error, LocalizedError {
        case noLocalFolder
        case localFolderUnavailable(String)
        case remoteFolderUnavailable(String)
        case cancelled
        public var errorDescription: String? {
            switch self {
            case .noLocalFolder: return "No local folder is attached to this sync."
            case .localFolderUnavailable(let s): return "The local folder is not available: \(s)"
            case .remoteFolderUnavailable(let s): return "The Unraid folder is not available: \(s)"
            case .cancelled: return "Cancelled"
            }
        }
    }

    private struct LocalItem { var url: URL; var mtime: Date; var size: Int64 }
    fileprivate enum Action { case upload(String), download(String), deleteLocal(String), deleteRemote(String), conflict(String), mkdirRemote(String), mkdirLocal(String) }

    private let client: GatewayClient
    private let pair: SyncPair
    private let onProgress: (@Sendable (Progress) -> Void)?
    /// Label used to name the losing copy in "keep both" conflicts ("Mac", "iPhone"…).
    private let deviceTag: String
    private var cancelled = false

    public init(client: GatewayClient, pair: SyncPair, deviceTag: String, onProgress: (@Sendable (Progress) -> Void)? = nil) {
        self.client = client; self.pair = pair; self.deviceTag = deviceTag; self.onProgress = onProgress
    }

    public func cancel() { cancelled = true }

    /// Runs the pair once. Never throws for per-file problems: they end up in the summary/records.
    public func run(trigger: String) async -> (SyncRunSummary, [SyncFileRecord]) {
        let started = Date()
        var records: [SyncFileRecord] = []
        var summary = SyncRunSummary(trigger: trigger)
        defer { summary.durationMs = Int64(Date().timeIntervalSince(started) * 1000) }
        guard pair.localBookmark != nil else {
            summary.status = .failed; summary.error = Failure.noLocalFolder.localizedDescription; return (summary, records)
        }
        guard let root = pair.resolveLocalURL() else {
            summary.status = .failed; summary.error = Failure.localFolderUnavailable("bookmark cannot be resolved").localizedDescription; return (summary, records)
        }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: root.path) else {
            summary.status = .failed; summary.error = Failure.localFolderUnavailable(root.path).localizedDescription; return (summary, records)
        }
        report(Progress(phase: "scanning", done: 0, total: 0, current: nil, bytes: 0))

        // 1. Local tree.
        let (localFiles, localDirs) = scanLocal(root)
        // 2. Remote tree (create the remote root when it does not exist and we may write).
        var remoteFiles: [String: FSEntry] = [:]
        var remoteDirs = Set<String>()
        do {
            try await ensureRemoteRoot()
            try await scanRemote(pair.remotePath, prefix: "", files: &remoteFiles, dirs: &remoteDirs)
        } catch {
            summary.status = .failed; summary.error = Failure.remoteFolderUnavailable(error.localizedDescription).localizedDescription
            Diag.error("sync", "\(pair.localLabel): remote scan", error)
            return (summary, records)
        }
        var state = SyncStore.state(pair.id)
        let canUp = pair.mode != .down, canDown = pair.mode != .up

        // 3. Plan.
        var actions: [Action] = []
        for d in localDirs where !remoteDirs.contains(d) && canUp { actions.append(.mkdirRemote(d)) }
        for d in remoteDirs where !localDirs.contains(d) && canDown { actions.append(.mkdirLocal(d)) }
        let all = Set(localFiles.keys).union(remoteFiles.keys).union(state.entries.keys)
        for rel in all.sorted() {
            let l = localFiles[rel], r = remoteFiles[rel], s = state.entries[rel]
            switch (l, r) {
            case let (l?, nil):
                if s == nil {
                    if canUp { actions.append(.upload(rel)) }
                } else if pair.deletions == .mirror && canDown {
                    actions.append(.deleteLocal(rel))
                } else if canUp {
                    actions.append(.upload(rel))
                } else { _ = l }
            case let (nil, r?):
                if s == nil {
                    if canDown { actions.append(.download(rel)) }
                } else if pair.deletions == .mirror && canUp {
                    actions.append(.deleteRemote(rel))
                } else if canDown {
                    actions.append(.download(rel))
                } else { _ = r }
            case let (l?, r?):
                let localChanged = s == nil || !Self.sameTime(l.mtime, s!.localMtime) || l.size != s!.localSize
                let remoteChanged = s == nil || r.etag != s!.remoteEtag
                if s == nil, l.size == r.size, Self.sameTime(l.mtime, r.mtime) {
                    state.entries[rel] = .init(localMtime: l.mtime, localSize: l.size, remoteEtag: r.etag, remoteMtime: r.mtime, remoteSize: r.size)
                } else if !localChanged && !remoteChanged {
                    continue
                } else if localChanged && !remoteChanged {
                    actions.append(canUp ? .upload(rel) : .conflict(rel))
                } else if remoteChanged && !localChanged {
                    actions.append(canDown ? .download(rel) : .conflict(rel))
                } else {
                    actions.append(.conflict(rel))
                }
            case (nil, nil):
                state.entries[rel] = nil   // gone on both sides
            }
        }

        // 4. Execute: directories first (serially), then files with a little concurrency.
        var done = 0
        let total = actions.count
        report(Progress(phase: "syncing", done: 0, total: total, current: nil, bytes: 0))
        for a in actions {
            guard case .mkdirRemote(let d) = a else { if case .mkdirLocal(let d) = a { try? FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true) }; continue }
            do { _ = try await client.mkdir(remote(d), parents: true) } catch { records.append(.init(path: remote(d), direction: .up, outcome: .failed, detail: error.localizedDescription)); summary.errors += 1 }
            done += 1
        }
        let fileActions = actions.filter { if case .mkdirRemote = $0 { return false }; if case .mkdirLocal = $0 { return false }; return true }
        var bytes: Int64 = 0
        for a in fileActions {
            if cancelled { summary.status = .partial; summary.error = "cancelled"; break }
            let rel: String
            switch a { case .upload(let p), .download(let p), .deleteLocal(let p), .deleteRemote(let p), .conflict(let p): rel = p; default: continue }
            report(Progress(phase: "syncing", done: done, total: total, current: rel, bytes: bytes))
            do {
                switch a {
                case .upload:
                    let l = localFiles[rel]!
                    let e = try await client.upload(fileURL: l.url, to: remote(rel), overwrite: true, mtime: l.mtime)
                    state.entries[rel] = .init(localMtime: l.mtime, localSize: l.size, remoteEtag: e.etag, remoteMtime: e.mtime, remoteSize: e.size)
                    records.append(.init(path: remote(rel), direction: .up, bytes: l.size)); bytes += l.size; summary.files += 1
                    ActivityLog.append(ActivityEvent(serverID: pair.serverID, path: remote(rel), kind: .upload, bytes: l.size))
                case .download:
                    let r = remoteFiles[rel]!
                    let dest = root.appendingPathComponent(rel)
                    try await downloadInto(dest, remotePath: remote(rel), mtime: r.mtime)
                    let (m, sz) = Self.attrs(dest)
                    state.entries[rel] = .init(localMtime: m, localSize: sz, remoteEtag: r.etag, remoteMtime: r.mtime, remoteSize: r.size)
                    records.append(.init(path: remote(rel), direction: .down, bytes: r.size)); bytes += r.size; summary.files += 1
                    ActivityLog.append(ActivityEvent(serverID: pair.serverID, path: remote(rel), kind: .download, bytes: r.size))
                case .deleteLocal:
                    try FileManager.default.trashOrRemove(root.appendingPathComponent(rel))
                    state.entries[rel] = nil
                    records.append(.init(path: remote(rel), direction: .delete, detail: "local")); summary.files += 1
                case .deleteRemote:
                    try await client.delete(remote(rel), recursive: false)
                    state.entries[rel] = nil
                    records.append(.init(path: remote(rel), direction: .delete, detail: "Unraid")); summary.files += 1
                    ActivityLog.append(ActivityEvent(serverID: pair.serverID, path: remote(rel), kind: .delete))
                case .conflict:
                    let (rec, moved) = try await resolveConflict(rel, local: localFiles[rel]!, remote: remoteFiles[rel]!, root: root, state: &state)
                    records.append(contentsOf: rec); bytes += moved; summary.conflicts += 1; summary.files += rec.filter { $0.outcome == .ok }.count
                default: break
                }
            } catch {
                summary.errors += 1
                records.append(.init(path: remote(rel), direction: a.direction, outcome: .failed, detail: error.localizedDescription))
                ActivityLog.append(ActivityEvent(serverID: pair.serverID, path: remote(rel), kind: a.direction == .down ? .download : .upload, error: error.localizedDescription))
                Diag.error("sync", "\(pair.localLabel): \(rel)", error)
            }
            done += 1
        }
        summary.bytes = bytes
        SyncStore.saveState(pair.id, state)
        if summary.status != .partial { summary.status = summary.errors > 0 ? (summary.files > 0 ? .partial : .failed) : .ok }
        if summary.errors > 0, summary.error == nil { summary.error = records.first { $0.outcome == .failed }?.detail }
        report(Progress(phase: "done", done: total, total: total, current: nil, bytes: bytes))
        Diag.info("sync", "\(pair.localLabel) ↔ \(pair.remotePath): \(summary.status.rawValue), \(summary.files) files, \(bytes) bytes, \(summary.conflicts) conflicts, \(summary.errors) errors, \(trigger)")
        return (summary, records)
    }

    // MARK: helpers

    private func report(_ p: Progress) { onProgress?(p) }
    private func remote(_ rel: String) -> String { rel.isEmpty ? pair.remotePath : pair.remotePath + "/" + rel }

    private static func sameTime(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) < 2
    }

    public static func attrs(_ url: URL) -> (Date, Int64) {
        let a = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        return ((a[.modificationDate] as? Date) ?? Date(), (a[.size] as? Int64) ?? Int64((a[.size] as? Int) ?? 0))
    }

    private func excluded(_ name: String, _ rel: String) -> Bool {
        if name == ".DS_Store" || name.hasSuffix(".gwpart") || name == "Icon\r" || name.hasPrefix("._") { return true }
        for pat in pair.excludes where !pat.isEmpty {
            if fnmatch(pat, name, FNM_CASEFOLD) == 0 || fnmatch(pat, rel, FNM_CASEFOLD | FNM_PATHNAME) == 0 { return true }
        }
        return false
    }

    private func scanLocal(_ root: URL) -> ([String: LocalItem], Set<String>) {
        var files: [String: LocalItem] = [:]
        var dirs = Set<String>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .isPackageKey, .isSymbolicLinkKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return (files, dirs) }
        let base = root.standardizedFileURL.path
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let full = u.standardizedFileURL.path
            guard full.hasPrefix(base) else { continue }
            let rel = String(full.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rel.isEmpty { continue }
            if excluded(u.lastPathComponent, rel) { if v?.isDirectory == true { en.skipDescendants() }; continue }
            if v?.isSymbolicLink == true { continue }
            if v?.isDirectory == true && v?.isPackage != true { dirs.insert(rel); continue }
            guard v?.isRegularFile == true || v?.isPackage == true else { continue }
            if v?.isPackage == true { en.skipDescendants(); continue }   // bundles are not synced file by file
            files[rel] = LocalItem(url: u, mtime: v?.contentModificationDate ?? Date(), size: Int64(v?.fileSize ?? 0))
        }
        return (files, dirs)
    }

    private func ensureRemoteRoot() async throws {
        do { _ = try await client.stat(pair.remotePath) } catch GatewayError.notFound {
            guard pair.mode != .down else { throw Failure.remoteFolderUnavailable(pair.remotePath) }
            _ = try await client.mkdir(pair.remotePath, parents: true)
        }
    }

    private func scanRemote(_ path: String, prefix: String, files: inout [String: FSEntry], dirs: inout Set<String>) async throws {
        let page = try await client.list(path, hidden: true)
        for e in page.entries {
            let rel = prefix.isEmpty ? e.name : prefix + "/" + e.name
            if excluded(e.name, rel) { continue }
            if e.isDirectory {
                dirs.insert(rel)
                try await scanRemote(e.path, prefix: rel, files: &files, dirs: &dirs)
            } else {
                files[rel] = e
            }
        }
    }

    private func downloadInto(_ dest: URL, remotePath: String, mtime: Date) async throws {
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.lastPathComponent).gwpart")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try await client.download(remotePath, to: tmp)
        if FileManager.default.fileExists(atPath: dest.path) { _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp) } else { try FileManager.default.moveItem(at: tmp, to: dest) }
        try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: dest.path)
    }

    /// Applies the pair's conflict policy to one path that changed on both sides.
    private func resolveConflict(_ rel: String, local l: LocalItem, remote r: FSEntry, root: URL, state: inout SyncStore.State) async throws -> ([SyncFileRecord], Int64) {
        let path = remote(rel)
        switch pair.conflicts {
        case .ask:
            return ([.init(path: path, direction: .conflict, outcome: .conflict, detail: "changed on both sides — decide in the app")], 0)
        case .keepExisting:
            // Whatever is at the destination of the pair's direction stays; two-way keeps both as they are.
            state.entries[rel] = .init(localMtime: l.mtime, localSize: l.size, remoteEtag: r.etag, remoteMtime: r.mtime, remoteSize: r.size)
            return ([.init(path: path, direction: .conflict, outcome: .skipped, detail: "kept existing copies")], 0)
        case .newest:
            if l.mtime >= r.mtime, pair.mode != .down {
                let e = try await client.upload(fileURL: l.url, to: path, overwrite: true, mtime: l.mtime)
                state.entries[rel] = .init(localMtime: l.mtime, localSize: l.size, remoteEtag: e.etag, remoteMtime: e.mtime, remoteSize: e.size)
                return ([.init(path: path, direction: .up, bytes: l.size, outcome: .ok, detail: "newest wins (\(deviceTag))")], l.size)
            } else {
                try await downloadInto(l.url, remotePath: path, mtime: r.mtime)
                let (m, sz) = Self.attrs(l.url)
                state.entries[rel] = .init(localMtime: m, localSize: sz, remoteEtag: r.etag, remoteMtime: r.mtime, remoteSize: r.size)
                return ([.init(path: path, direction: .down, bytes: r.size, outcome: .ok, detail: "newest wins (Unraid)")], r.size)
            }
        case .keepBoth:
            // The local copy becomes "name (<device>).ext" on both sides; the Unraid copy takes the original name on both sides.
            let ext = (rel as NSString).pathExtension
            let stem = (rel as NSString).deletingPathExtension
            let renamedRel = ext.isEmpty ? "\(stem) (\(deviceTag))" : "\(stem) (\(deviceTag)).\(ext)"
            let renamedLocal = root.appendingPathComponent(renamedRel)
            try FileManager.default.moveItem(at: l.url, to: renamedLocal)
            var recs: [SyncFileRecord] = []
            var moved: Int64 = 0
            let e = try await client.upload(fileURL: renamedLocal, to: remote(renamedRel), overwrite: true, mtime: l.mtime)
            state.entries[renamedRel] = .init(localMtime: l.mtime, localSize: l.size, remoteEtag: e.etag, remoteMtime: e.mtime, remoteSize: e.size)
            recs.append(.init(path: remote(renamedRel), direction: .up, bytes: l.size, outcome: .conflict, detail: "kept both: your copy renamed")); moved += l.size
            try await downloadInto(root.appendingPathComponent(rel), remotePath: path, mtime: r.mtime)
            let (m, sz) = Self.attrs(root.appendingPathComponent(rel))
            state.entries[rel] = .init(localMtime: m, localSize: sz, remoteEtag: r.etag, remoteMtime: r.mtime, remoteSize: r.size)
            recs.append(.init(path: path, direction: .down, bytes: r.size, outcome: .conflict, detail: "kept both: Unraid copy")); moved += r.size
            return (recs, moved)
        }
    }
}

private extension SyncEngine.Action {
    var direction: SyncFileRecord.Direction {
        switch self {
        case .upload, .mkdirRemote: return .up
        case .download, .mkdirLocal: return .down
        case .deleteLocal, .deleteRemote: return .delete
        case .conflict: return .conflict
        }
    }
}

extension FileManager {
    /// Moves to the Trash where there is one (macOS), removes otherwise.
    func trashOrRemove(_ url: URL) throws {
        #if os(macOS)
        do { try trashItem(at: url, resultingItemURL: nil); return } catch {}
        #endif
        try removeItem(at: url)
    }
}
