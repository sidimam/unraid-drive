import Foundation
import FileProvider
import UnraidGatewayKit

/// Maps stable File Provider item identifiers to gateway paths and back.
///
/// The gateway addresses items by path, but File Provider identifiers must
/// survive renames and moves. Each path gets a UUID the first time it is seen;
/// moves rewrite the path side of the mapping and keep the identifier. The
/// index also remembers the last listing of every directory so the change
/// enumerator can detect deletions (the gateway feed reports modified
/// directories, not the removed names).
actor ItemIndex {
    private struct Snapshot: Codable {
        var idToPath: [String: String] = [:]
        var listings: [String: [String]] = [:]
        var retired: [String] = []
    }
    /// Locally generated identifiers superseded by server ids: reported as deletions so the
    /// system drops the duplicates it would otherwise keep.
    private var retired: Set<String> = []

    private let fileURL: URL
    private var idToPath: [String: String] = [:]
    private var pathToID: [String: String] = [:]
    private var listings: [String: [String]] = [:]
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    init(domainID: String) {
        let base = AppGroup.containerURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FileProvider", isDirectory: true).appendingPathComponent(domainID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: fileURL), let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            idToPath = snap.idToPath
            listings = snap.listings
            retired = Set(snap.retired)
            for (id, p) in snap.idToPath { pathToID[p] = id }
        }
    }

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
        markDirty()
    }

    func identifier(for path: String) -> NSFileProviderItemIdentifier {
        let p = GatewayPath.clean(path)
        if p == "/" { return .rootContainer }
        if let id = pathToID[p] { return NSFileProviderItemIdentifier(id) }
        let id = UUID().uuidString
        pathToID[p] = id
        idToPath[id] = p
        markDirty()
        return NSFileProviderItemIdentifier(id)
    }

    func path(for identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer { return "/" }
        return idToPath[identifier.rawValue]
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
        listings[GatewayPath.clean(dir)] = names
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
        let snap = Snapshot(idToPath: idToPath, listings: listings, retired: Array(retired))
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
