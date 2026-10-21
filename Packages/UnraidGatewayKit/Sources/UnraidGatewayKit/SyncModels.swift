import Foundation

// MARK: - Sync pairs (1.5)

/// What a pair syncs.
public enum SyncKind: String, Codable, Sendable, CaseIterable {
    /// A local folder ↔ an Unraid folder (Mac).
    case folder
    /// The device's Photos library → an Unraid folder (originals, incremental).
    case photos
    /// The device's Downloads folder → an Unraid folder (iPhone, iPad, Vision Pro).
    case downloads
}

/// Direction of a pair.
public enum SyncMode: String, Codable, Sendable, CaseIterable {
    case up      // device → Unraid
    case down    // Unraid → device
    case both    // two-way
}

/// What to do when a file changed on both sides (or exists on both at the first run with different contents).
public enum ConflictPolicy: String, Codable, Sendable, CaseIterable {
    case newest      // the most recently modified copy wins
    case keepBoth    // keep both, the loser renamed "name (Mac).ext" / "name (Unraid).ext"
    case keepExisting // keep the copy already at the destination, skip
    case ask         // record the conflict, touch nothing until the user decides
}

/// What to do with files deleted on one side.
public enum DeletionPolicy: String, Codable, Sendable, CaseIterable {
    case mirror  // delete on the other side too
    case keep    // never delete anything
}

/// When a pair runs.
public enum SyncSchedule: String, Codable, Sendable, CaseIterable {
    case continuous  // watch for changes + periodic scan
    case hourly
    case daily
    case manual
}

/// One sync pair, as the app stores it (the gateway keeps a copy without the local bookmark).
public struct SyncPair: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var serverID: String
    public var kind: SyncKind
    /// What the user sees for the local side ("~/Desktop", "Photos library", "Downloads").
    public var localLabel: String
    /// Security-scoped bookmark of the local folder (folder / downloads kinds).
    public var localBookmark: Data?
    public var remotePath: String
    public var mode: SyncMode
    public var conflicts: ConflictPolicy
    public var deletions: DeletionPolicy
    public var schedule: SyncSchedule
    /// Patterns (glob-ish, case-insensitive) never synced; `.DS_Store` and `.gwpart` always are.
    public var excludes: [String]
    public var wifiOnly: Bool
    public var enabled: Bool
    /// Who paused the pair on the gateway (web UI / console), when it was; nil otherwise.
    public var pausedByGateway: String?
    public var createdAt: Date
    public var lastRun: SyncRunSummary?

    public init(serverID: String, kind: SyncKind, localLabel: String, localBookmark: Data? = nil, remotePath: String, mode: SyncMode = .up,
                conflicts: ConflictPolicy = .newest, deletions: DeletionPolicy = .keep, schedule: SyncSchedule = .continuous, excludes: [String] = [], wifiOnly: Bool = false) {
        id = UUID().uuidString; self.serverID = serverID; self.kind = kind; self.localLabel = localLabel; self.localBookmark = localBookmark
        self.remotePath = remotePath; self.mode = mode; self.conflicts = conflicts; self.deletions = deletions; self.schedule = schedule
        self.excludes = excludes; self.wifiOnly = wifiOnly; enabled = true; createdAt = Date()
    }

    /// Both enabled locally and not paused on the gateway.
    public var isActive: Bool { enabled && pausedByGateway == nil }

    /// Security-scoped bookmark of a folder the user picked (plain bookmark where the process has
    /// no sandbox entitlement for scoped bookmarks, e.g. unsigned debug builds).
    public static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        if let d = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { return d }
        #endif
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves the local folder; the caller must balance `startAccessingSecurityScopedResource`.
    public func resolveLocalURL() -> URL? {
        guard let data = localBookmark else { return nil }
        var stale = false
        #if os(macOS)
        if let u = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return u }
        #endif
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    public var symbol: String {
        switch kind {
        case .folder: return "arrow.triangle.2.circlepath.circle"
        case .photos: return "photo.on.rectangle.angled"
        case .downloads: return "arrow.down.circle"
        }
    }
}

/// Outcome of one run.
public struct SyncRunSummary: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case ok, partial, failed, skipped }
    public var at: Date
    public var durationMs: Int64
    public var files: Int
    public var bytes: Int64
    public var conflicts: Int
    public var errors: Int
    public var status: Status
    public var error: String?
    public var trigger: String
    public init(at: Date = Date(), durationMs: Int64 = 0, files: Int = 0, bytes: Int64 = 0, conflicts: Int = 0, errors: Int = 0, status: Status = .ok, error: String? = nil, trigger: String = "manual") {
        self.at = at; self.durationMs = durationMs; self.files = files; self.bytes = bytes; self.conflicts = conflicts; self.errors = errors; self.status = status; self.error = error; self.trigger = trigger
    }
}

/// One file the run moved (or failed to), reported to the gateway and shown in the app.
public struct SyncFileRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Direction: String, Codable, Sendable { case up, down, delete, conflict }
    public enum Outcome: String, Codable, Sendable { case ok, conflict, failed, skipped }
    public var id: String { path + "|" + direction.rawValue + "|" + time.timeIntervalSince1970.description }
    public var time: Date
    public var path: String       // Unraid-side path
    public var direction: Direction
    public var bytes: Int64
    public var outcome: Outcome
    public var detail: String?
    public init(time: Date = Date(), path: String, direction: Direction, bytes: Int64 = 0, outcome: Outcome = .ok, detail: String? = nil) {
        self.time = time; self.path = path; self.direction = direction; self.bytes = bytes; self.outcome = outcome; self.detail = detail
    }
}

// MARK: - Gateway DTOs (unraid-gateway 0.14 `/api/v1/syncs`)

public struct RemoteSync: Codable, Sendable {
    public var id: String
    public var deviceId: String?
    public var user: String?
    public var kind: String
    public var localLabel: String
    public var remotePath: String
    public var mode: String
    public var enabled: Bool
    public var disabledBy: String?
    public var runs: Int64?
    public var totalFiles: Int64?
    public var totalBytes: Int64?
}

// MARK: - Store: pairs + per-pair state, in the app group (shared with the extension for the Activity feed)

/// Pairs are kept in `syncs.json`; each pair's last-synced state in `sync-state/<id>.json`.
public enum SyncStore {
    /// The app group container; without one (tests, unsigned builds) a folder under Application Support.
    /// Tests point this at a temporary folder.
    nonisolated(unsafe) public static var overrideDirectory: URL?
    static var dir: URL? {
        if let o = overrideDirectory { return o }
        if let u = AppGroup.containerURL, FileManager.default.isWritableFile(atPath: u.path) { return u }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let u = base.appendingPathComponent("UnraidDrive", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var pairsURL: URL? { dir?.appendingPathComponent("syncs.json") }
    static func stateURL(_ id: String) -> URL? { dir?.appendingPathComponent("sync-state", isDirectory: true).appendingPathComponent(id + ".json") }
    private static let queue = DispatchQueue(label: "sync-store")
    public static let changedNotification = Notification.Name("com.sdimambro.unraid-drive.syncs.changed")

    public static func all() -> [SyncPair] {
        queue.sync { load() }
    }
    public static func pairs(for serverID: String) -> [SyncPair] { all().filter { $0.serverID == serverID } }
    public static func pair(_ id: String) -> SyncPair? { all().first { $0.id == id } }

    public static func save(_ pair: SyncPair) {
        queue.sync {
            var all = load()
            if let i = all.firstIndex(where: { $0.id == pair.id }) { all[i] = pair } else { all.append(pair) }
            store(all)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: changedNotification, object: pair.id) }
    }

    public static func remove(_ id: String) {
        queue.sync {
            store(load().filter { $0.id != id })
            if let u = stateURL(id) { try? FileManager.default.removeItem(at: u) }
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: changedNotification, object: id) }
    }

    public static func removeAll(for serverID: String) {
        for p in pairs(for: serverID) { remove(p.id) }
    }

    private static func load() -> [SyncPair] {
        guard let u = pairsURL, let d = try? Data(contentsOf: u) else { return [] }
        return (try? GatewayJSON.decoder.decode([SyncPair].self, from: d)) ?? []
    }
    private static func store(_ pairs: [SyncPair]) {
        guard let u = pairsURL else { return }
        if let d = try? GatewayJSON.encoder.encode(pairs) { try? d.write(to: u, options: .atomic) }
    }

    // State: what each side looked like the last time the pair was in sync, keyed by relative path.
    public struct Entry: Codable, Sendable, Hashable {
        public var localMtime: Date?
        public var localSize: Int64?
        public var remoteEtag: String?
        public var remoteMtime: Date?
        public var remoteSize: Int64?
        public var syncedAt: Date
        public init(localMtime: Date?, localSize: Int64?, remoteEtag: String?, remoteMtime: Date?, remoteSize: Int64?, syncedAt: Date = Date()) {
            self.localMtime = localMtime; self.localSize = localSize; self.remoteEtag = remoteEtag; self.remoteMtime = remoteMtime; self.remoteSize = remoteSize; self.syncedAt = syncedAt
        }
    }
    public struct State: Codable, Sendable {
        public var entries: [String: Entry]
        /// Photos backup: asset localIdentifier → "modificationDate|resourceCount" of the last upload.
        public var assets: [String: String]
        public init() { entries = [:]; assets = [:] }
    }
    public static func state(_ id: String) -> State {
        queue.sync {
            guard let u = stateURL(id), let d = try? Data(contentsOf: u) else { return State() }
            return (try? GatewayJSON.decoder.decode(State.self, from: d)) ?? State()
        }
    }
    public static func saveState(_ id: String, _ state: State) {
        queue.sync {
            guard let u = stateURL(id) else { return }
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? GatewayJSON.encoder.encode(state) { try? d.write(to: u, options: .atomic) }
        }
    }

    // Recent files per pair (what the app shows under a pair), ≤ 100.
    public static func recentFiles(_ id: String) -> [SyncFileRecord] {
        queue.sync {
            guard let u = dir?.appendingPathComponent("sync-state/\(id).files.json"), let d = try? Data(contentsOf: u) else { return [] }
            return (try? GatewayJSON.decoder.decode([SyncFileRecord].self, from: d)) ?? []
        }
    }
    public static func appendFiles(_ id: String, _ files: [SyncFileRecord]) {
        guard !files.isEmpty else { return }
        queue.sync {
            guard let u = dir?.appendingPathComponent("sync-state/\(id).files.json") else { return }
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            var all = ((try? Data(contentsOf: u)).flatMap { try? GatewayJSON.decoder.decode([SyncFileRecord].self, from: $0) }) ?? []
            all = (files.sorted { $0.time > $1.time } + all)
            if all.count > 100 { all = Array(all.prefix(100)) }
            if let d = try? GatewayJSON.encoder.encode(all) { try? d.write(to: u, options: .atomic) }
        }
    }
}
