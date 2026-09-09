import Foundation
import FileProvider
import UnraidGatewayKit

/// Sync anchor = the gateway change-feed cursor plus, while a scan is being
/// paged, the resume point. Encoded as "cursor|after".
struct SyncAnchor {
    var cursor: Int64
    var after: String?

    init(cursor: Int64, after: String? = nil) { self.cursor = cursor; self.after = after }

    init?(_ data: NSFileProviderSyncAnchor) {
        guard let s = String(data: data.rawValue, encoding: .utf8) else { return nil }
        let parts = s.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let c = Int64(parts[0]) else { return nil }
        cursor = c
        after = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    var raw: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(Data("\(cursor)|\(after ?? "")".utf8))
    }

    static var now: SyncAnchor { SyncAnchor(cursor: Int64(Date().timeIntervalSince1970 * 1_000_000_000) - 2_000_000_000) }
}

/// Enumerates one directory (or the root, whose children are the shares).
final class DirectoryEnumerator: NSObject, NSFileProviderEnumerator {
    private let ext: FileProviderExtension
    private let container: NSFileProviderItemIdentifier

    init(ext: FileProviderExtension, container: NSFileProviderItemIdentifier) {
        self.ext = ext; self.container = container
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            guard let path = await ext.index.path(for: container) else { observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem)); return }
            do {
                guard let client = ext.client else { throw NSFileProviderError(.notAuthenticated) }
                let listing = try await client.list(path)
                var items: [FileProviderItem] = []
                for e in listing.entries { items.append(await ext.makeItem(e)) }
                let vanished = await ext.index.vanishedIdentifiers(in: path, current: listing.entries.map(\.name))
                await ext.index.rememberListing(path, names: listing.entries.map(\.name))
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                // A plain listing cannot delete items; the working set can. Wake it up.
                if !vanished.isEmpty { ext.nudgeWorkingSet() }
            } catch { observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            guard let path = await ext.index.path(for: container) else { observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem)); return }
            guard let a = SyncAnchor(anchor) else { observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired)); return }
            do {
                guard let client = ext.client else { throw NSFileProviderError(.notAuthenticated) }
                // Cheap check first: has this directory itself changed?
                let page = try await client.changes(path, since: a.cursor, after: a.after, cursor: a.after == nil ? nil : a.cursor, limit: 5000)
                var updated: [NSFileProviderItem] = []
                var deleted: [NSFileProviderItemIdentifier] = []
                // The root lists the mounted shares. Mounts change only when the container is
                // recreated, which the change feed (mtime based) cannot see, so the root is
                // always re-listed: it is a handful of entries and costs one millisecond.
                let dirChanged = path == "/" || page.dirs.contains(path)
                if dirChanged {
                    let listing = try await client.list(path)
                    deleted = await ext.index.vanishedIdentifiers(in: path, current: listing.entries.map(\.name))
                    for e in listing.entries { updated.append(await ext.makeItem(e)) }
                    await ext.index.rememberListing(path, names: listing.entries.map(\.name))
                } else {
                    for f in page.files where GatewayPath.parent(f.path) == path { updated.append(await ext.makeItem(f)) }
                    for d in page.dirs where GatewayPath.parent(d) == path {
                        if let e = try? await client.stat(d) { updated.append(await ext.makeItem(e)) }
                    }
                }
                deleted += await ext.index.takeRetired()
                if !updated.isEmpty { observer.didUpdate(updated) }
                if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted) }
                if page.truncated, let next = page.next {
                    observer.finishEnumeratingChanges(upTo: SyncAnchor(cursor: page.cursor, after: next).raw, moreComing: true)
                } else {
                    observer.finishEnumeratingChanges(upTo: SyncAnchor(cursor: page.cursor).raw, moreComing: false)
                }
            } catch { observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(SyncAnchor.now.raw)
    }
}

/// The working set: everything the system has materialized. With gateway 0.5+
/// the id-based journal (`/fs/changes?seq=`) tells us exactly which items were
/// created, modified, moved or deleted, instantly and without walking the tree.
/// Older gateways fall back to the mtime walk of the paginated change feed.
final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    private let ext: FileProviderExtension
    init(ext: FileProviderExtension) { self.ext = ext }
    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    /// Journal anchors are "seq:<n>"; anything else (a legacy anchor) restarts from 0.
    private static func seq(from anchor: NSFileProviderSyncAnchor) -> Int64 {
        guard let s = String(data: anchor.rawValue, encoding: .utf8), s.hasPrefix("seq:") else { return 0 }
        return Int64(s.dropFirst(4)) ?? 0
    }
    private static func anchor(seq: Int64) -> NSFileProviderSyncAnchor { NSFileProviderSyncAnchor(Data("seq:\(seq)".utf8)) }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                guard let client = ext.client else { throw NSFileProviderError(.notAuthenticated) }
                let since = Self.seq(from: anchor)
                let page: JournalPage
                do {
                    page = try await client.journal(seq: since, limit: 1000)
                } catch let e as GatewayError where isLegacy(e) {
                    await legacyChanges(client: client, observer: observer, anchor: anchor)
                    return
                }
                if page.reset {
                    if since == 0 {
                        // First sync: nothing to replay, directory listings populate the tree.
                        let retired = await ext.index.takeRetired()
                        if !retired.isEmpty { observer.didDeleteItems(withIdentifiers: retired) }
                        observer.finishEnumeratingChanges(upTo: Self.anchor(seq: page.seq), moreComing: false)
                    } else {
                        // The journal no longer covers our anchor: the system re-enumerates everything.
                        observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
                    }
                    return
                }
                var updated: [NSFileProviderItem] = []
                var deleted: [NSFileProviderItemIdentifier] = []
                for c in page.changes {
                    switch c.kind {
                    case .delete:
                        deleted.append(NSFileProviderItemIdentifier(c.id))
                        await ext.index.remove(path: c.path)
                    case .upsert, .move:
                        if let e = c.entry {
                            if let old = c.oldPath { await ext.index.move(from: old, to: e.path) }
                            updated.append(await ext.makeItem(e))
                        } else {
                            deleted.append(NSFileProviderItemIdentifier(c.id))
                        }
                    }
                }
                deleted += await ext.index.takeRetired()
                if !updated.isEmpty { observer.didUpdate(updated) }
                if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted) }
                observer.finishEnumeratingChanges(upTo: Self.anchor(seq: page.seq), moreComing: page.truncated)
            } catch { observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
        }
    }

    /// A gateway without the index answers `seq=` with the legacy walk payload, which fails to decode.
    private func isLegacy(_ e: GatewayError) -> Bool {
        if case .decoding = e { return true }
        if case .http(let code, _) = e, code == 400 { return true }
        return false
    }

    /// Legacy feed (gateway < 0.5): mtime walk, deletions inferred by re-listing changed directories.
    private func legacyChanges(client: GatewayClient, observer: NSFileProviderChangeObserver, anchor: NSFileProviderSyncAnchor) async {
        let a = SyncAnchor(anchor) ?? SyncAnchor.now
        do {
            let page = try await client.changes("/", since: a.cursor, after: a.after, cursor: a.after == nil ? nil : a.cursor, limit: 5000)
            var updated: [NSFileProviderItem] = []
            var deleted: [NSFileProviderItemIdentifier] = []
            if a.after == nil, let root = try? await client.list("/") {
                deleted += await ext.index.vanishedIdentifiers(in: "/", current: root.entries.map(\.name))
                await ext.index.rememberListing("/", names: root.entries.map(\.name))
                for e in root.entries { updated.append(await ext.makeItem(e)) }
            }
            for f in page.files { updated.append(await ext.makeItem(f)) }
            var relisted = 0
            for d in page.dirs where d != "/" {
                guard await ext.index.previousListing(d) != nil, relisted < 40 else { continue }
                relisted += 1
                if let listing = try? await client.list(d) {
                    deleted += await ext.index.vanishedIdentifiers(in: d, current: listing.entries.map(\.name))
                    await ext.index.rememberListing(d, names: listing.entries.map(\.name))
                    if let e = try? await client.stat(d) { updated.append(await ext.makeItem(e)) }
                }
            }
            if !updated.isEmpty { observer.didUpdate(updated) }
            if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted) }
            if page.truncated, let next = page.next {
                observer.finishEnumeratingChanges(upTo: SyncAnchor(cursor: page.cursor, after: next).raw, moreComing: true)
            } else {
                observer.finishEnumeratingChanges(upTo: SyncAnchor(cursor: page.cursor).raw, moreComing: false)
            }
        } catch { observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.anchor(seq: 0))
    }
}
