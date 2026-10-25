import Foundation
import FileProvider
import UnraidGatewayKit

/// Maps stable File Provider item identifiers to gateway paths and back.
///
/// The gateway addresses items by path, but File Provider identifiers must
/// survive renames and moves. Gateway 0.5+ items carry a stable server id; older gateways get a
/// local UUID the first time a path is seen. Moves rewrite the path side of the mapping and keep
/// the identifier. The index also remembers the last listing of recently viewed directories so
/// the change enumerator can detect deletions. Bounded (1.5.2): see `maxIDs`.
actor ItemIndex {
    /// 1.5.2: the index is a bounded cache. Until 1.5 it remembered every item the gateway's journal
    /// ever reported (every download on the NAS) and every directory listing, for ever, and loaded it
    /// all at launch: on iPhone and iPad, where a File Provider extension has a hard 20 MB memory
    /// limit, it grew past the limit and the system killed the extension before its first request
    /// (Files: "Content unavailable — unknown error"). Paths missing from the cache are resolved
    /// through the gateway (`/fs/item?id=`, gateway ids are stable), so evicting is safe.
    static let maxIDs = 2_500
    static let maxDirs = 200
    /// Directories with more names than this are not remembered (deletions there come from the journal).
    static let maxNamesPerDir = 2_000
    /// Total names kept across all remembered listings.
    static let maxTotalNames = 6_000
    /// An index file larger than this was written by an older build: dropped without being read
    /// (a full cache is about 400 KB on disk and 2–3 MB once decoded).
    static let maxFileBytes = 1_024 * 1024

    private struct Snapshot: Codable {
        var v: Int?
        var idToPath: [String: String] = [:]
        var listings: [String: [String]] = [:]
        var retired: [String] = []
        var idTouch: [String: UInt64]?
        var dirTouch: [String: UInt64]?
        var clock: UInt64?
    }
    /// Locally generated identifiers superseded by server ids: reported as deletions so the
    /// system drops the duplicates it would otherwise keep.
    private var retired: Set<String> = []

    private let fileURL: URL
    private var idToPath: [String: String] = [:]
    private var pathToID: [String: String] = [:]
    private var listings: [String: [String]] = [:]
    private var idTouch: [String: UInt64] = [:]
    private var dirTouch: [String: UInt64] = [:]
    private var clock: UInt64 = 0
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    init(domainID: String) {
        let base = AppGroup.containerURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FileProvider", isDirectory: true).appendingPathComponent(domainID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("index.json")
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > Self.maxFileBytes {
            // Reading it would already exceed the extension's memory limit: start from an empty cache.
            try? FileManager.default.removeItem(at: fileURL)
            Diag.warning("index", "dropped an oversized item index (\(size / 1024) KB) written by an older build; paths are resolved through the gateway again")
            return
        }
        if size > 0, let data = try? Data(contentsOf: fileURL), let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            idToPath = snap.idToPath
            listings = snap.listings
            retired = Set(snap.retired)
            idTouch = snap.idTouch ?? [:]
            dirTouch = snap.dirTouch ?? [:]
            clock = snap.clock ?? 0
            for (id, p) in snap.idToPath { pathToID[p] = id }
            // An older (still small) file may hold more than the limits: trimmed at the next write.
            dirty = snap.v != 2
        }
    }

    // MARK: Bounded cache

    private func touch(id: String) { clock &+= 1; idTouch[id] = clock }
    private func touch(dir: String) { clock &+= 1; dirTouch[dir] = clock }

    /// Keeps the most recently used entries; trims in batches so it is not done on every insert.
    private func trimIfNeeded(force: Bool = false) {
        let idSlack = force ? Self.maxIDs : Self.maxIDs + Self.maxIDs / 5
        if idToPath.count > idSlack {
            let keep = Set(idToPath.keys.sorted { (idTouch[$0] ?? 0) > (idTouch[$1] ?? 0) }.prefix(Self.maxIDs))
            for (id, p) in idToPath where !keep.contains(id) {
                idToPath[id] = nil
                if pathToID[p] == id { pathToID[p] = nil }
                idTouch[id] = nil
            }
            dirty = true
        }
        let dirSlack = force ? Self.maxDirs : Self.maxDirs + Self.maxDirs / 5
        if listings.count > dirSlack {
            let keep = Set(listings.keys.sorted { (dirTouch[$0] ?? 0) > (dirTouch[$1] ?? 0) }.prefix(Self.maxDirs))
            for d in listings.keys where !keep.contains(d) { listings[d] = nil; dirTouch[d] = nil }
            dirty = true
        }
        var total = listings.values.reduce(0) { $0 + $1.count }
        if total > Self.maxTotalNames {
            for d in listings.keys.sorted(by: { (dirTouch[$0] ?? 0) < (dirTouch[$1] ?? 0) }) where total > Self.maxTotalNames {
                total -= listings[d]?.count ?? 0
                listings[d] = nil; dirTouch[d] = nil
            }
            dirty = true
        }
        for id in idTouch.keys where idToPath[id] == nil { idTouch[id] = nil }
        for d in dirTouch.keys where listings[d] == nil { dirTouch[d] = nil }
    }

    /// True when the item is cached (the working set only reports changes the system can place).
    func knows(id: String) -> Bool { idToPath[id] != nil }
    /// True when the directory was listed recently (its children are on screen or were).
    func hasListing(_ dir: String) -> Bool { listings[GatewayPath.clean(dir)] != nil }

    // MARK: Identifiers

    /// Identifier for an entry: the gateway's stable id when it provides one (gateway 0.5+),
    /// otherwise a locally generated one that survives renames through `move`.
    func identifier(for entry: FSEntry) -> NSFileProviderItemIdentifier {
        if let sid = entry.itemID, !sid.isEmpty {
            remember(id: sid, path: entry.path)
            return NSFileProviderItemIdentifier(sid)
        }
        return identifier(for: entry.path)
    }

    /// Caches a server id ↔ path pair (and drops a stale mapping for the same path).
    func remember(id: String, path: String) {
        let p = GatewayPath.clean(path)
        if let old = pathToID[p], old != id {
            idToPath[old] = nil
            if UUID(uuidString: old) != nil { retired.insert(old) } // a legacy local id
        }
        if let oldPath = idToPath[id], oldPath != p { pathToID[oldPath] = nil }
        idToPath[id] = p
        pathToID[p] = id
        touch(id: id)
        trimIfNeeded()
        markDirty()
    }

    func identifier(for path: String) -> NSFileProviderItemIdentifier {
        let p = GatewayPath.clean(path)
        if p == "/" { return .rootContainer }
        if let id = pathToID[p] { touch(id: id); return NSFileProviderItemIdentifier(id) }
        let id = UUID().uuidString
        pathToID[p] = id
        idToPath[id] = p
        touch(id: id)
        trimIfNeeded()
        markDirty()
        return NSFileProviderItemIdentifier(id)
    }

    func path(for identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer { return "/" }
        guard let p = idToPath[identifier.rawValue] else { return nil }
        touch(id: identifier.rawValue)
        return p
    }

    /// Re-points an item (and everything below it) from one path to another.
    func move(from: String, to: String) {
        let f = GatewayPath.clean(from), t = GatewayPath.clean(to)
        let prefix = f + "/"
        for (id, p) in idToPath where p == f || p.hasPrefix(prefix) {
            let np = t + p.dropFirst(f.count)
            idToPath[id] = String(np)
            pathToID[p] = nil
            pathToID[String(np)] = id
        }
        for (dir, names) in listings where dir == f || dir.hasPrefix(prefix) {
            listings[dir] = nil
            listings[t + dir.dropFirst(f.count)] = names
        }
        markDirty()
    }

    func remove(path: String) {
        let p = GatewayPath.clean(path)
        let prefix = p + "/"
        for (id, q) in idToPath where q == p || q.hasPrefix(prefix) {
            idToPath[id] = nil
            pathToID[q] = nil
        }
        for dir in listings.keys where dir == p || dir.hasPrefix(prefix) { listings[dir] = nil }
        markDirty()
    }

    // MARK: Listings (for deletion detection)

    func rememberListing(_ dir: String, names: [String]) {
        let d = GatewayPath.clean(dir)
        guard names.count <= Self.maxNamesPerDir else {
            if listings[d] != nil { listings[d] = nil; dirTouch[d] = nil; markDirty() }
            return
        }
        if listings[d] == names { touch(dir: d); return }   // unchanged: no rewrite of the file
        listings[d] = names
        touch(dir: d)
        trimIfNeeded()
        markDirty()
    }

    func previousListing(_ dir: String) -> [String]? {
        listings[GatewayPath.clean(dir)]
    }

    /// Identifiers of names that were in the previous listing but not in `current`.
    func vanishedIdentifiers(in dir: String, current: [String]) -> [NSFileProviderItemIdentifier] {
        guard let old = previousListing(dir) else { return [] }
        let now = Set(current)
        var out: [NSFileProviderItemIdentifier] = []
        for name in old where !now.contains(name) {
            let p = GatewayPath.join(dir, name)
            if let id = pathToID[p] {
                out.append(NSFileProviderItemIdentifier(id))
                retired.insert(id)
                remove(path: p)
            }
        }
        return out
    }

    /// Legacy identifiers to report as deleted (cleared once taken).
    func takeRetired() -> [NSFileProviderItemIdentifier] {
        let out = retired.map { NSFileProviderItemIdentifier($0) }
        if !out.isEmpty { retired.removeAll(); markDirty() }
        return out
    }

    // MARK: Persistence

    private func markDirty() {
        dirty = true
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flush()
        }
    }

    func flush() {
        saveTask = nil
        guard dirty else { return }
        dirty = false
        trimIfNeeded(force: true)
        let snap = Snapshot(v: 2, idToPath: idToPath, listings: listings, retired: Array(retired), idTouch: idTouch, dirTouch: dirTouch, clock: clock)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
