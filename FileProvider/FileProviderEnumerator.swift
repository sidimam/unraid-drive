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
        super.init()
        // Build 45: a folder the system enumerates is "recently viewed": the extension re-lists it
        // live every 30 s for a while and pushes what changed through the working set (see
        // FileProviderExtension.watchRecentFolders), so files written straight on the NAS appear
        // without waiting for the gateway's directory scan.
        Task { if let path = await ext.path(for: container), path != "/" { await ext.noteViewed(path) } }
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            // A folder inside a share the user hid is gone as far as the system is concerned: only
            // then can it delete the (non-empty) share folder from the Files app / Finder.
            guard let path = await ext.path(for: container), ext.isVisible(path) else { observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem)); return }
            do {
                guard let client = ext.client else { throw NSFileProviderError(.notAuthenticated) }
                let entries = ext.visibleEntries(try await client.list(path).entries, in: path)
                var items: [FileProviderItem] = []
                for e in entries { items.append(await ext.makeItem(e)) }
                let vanished = await ext.index.vanishedIdentifiers(in: path, current: entries.map(\.name))
                await ext.index.rememberListing(path, names: entries.map(\.name))
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                // A plain listing cannot delete items; the working set can. Wake it up.
                if !vanished.isEmpty { ext.nudgeWorkingSet() }
            } catch { Diag.error("enumerate", "items of \(await ext.path(for: container) ?? container.rawValue)", error); observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            guard let path = await ext.path(for: container), ext.isVisible(path) else { observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem)); return }
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
                if path == "/" {
                    await ext.reconcileRoot(client: client, updated: &updated, deleted: &deleted)
                } else {
                    // Build 45: the folder itself is always re-listed live (one request). The feed
                    // above learns about files written straight on the NAS only at the gateway's next
                    // directory scan, which left an open Finder window showing a stale listing for
                    // minutes. Only entries that are new or newer than the anchor are reported,
                    // unless the feed says the directory changed (then everything is).
                    let listing = try await client.list(path)
                    let entries = ext.visibleEntries(listing.entries, in: path)
                    let previous = await ext.index.previousListing(path) ?? []
                    let since = Date(timeIntervalSince1970: Double(a.cursor) / 1_000_000_000)
                    deleted = await ext.index.vanishedIdentifiers(in: path, current: entries.map(\.name))
                    for e in entries where dirChanged || !previous.contains(e.name) || e.mtime > since { updated.append(await ext.makeItem(e)) }
                    await ext.index.rememberListing(path, names: entries.map(\.name))
                    // Subfolders the feed reports as changed deeper down still get their fresh stat.
                    for d in page.dirs where GatewayPath.parent(d) == path && ext.isVisible(d) && !entries.contains(where: { $0.path == d }) {
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
            } catch { Diag.error("enumerate", "changes of \(path)", error); observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
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
                        var updated: [NSFileProviderItem] = []
                        var retired: [NSFileProviderItemIdentifier] = []
                        await ext.reconcileRoot(client: client, updated: &updated, deleted: &retired)
                        retired += await ext.index.takeRetired()
                        if !updated.isEmpty { observer.didUpdate(updated) }
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
                // The root is re-listed on every working-set pass: shares appear when mounted and
                // disappear when unmounted or hidden by the user, none of which the journal reports.
                // It is one request for a handful of entries.
                await ext.reconcileRoot(client: client, updated: &updated, deleted: &deleted)
                for c in page.changes {
                    // Changes inside shares the user hid are not the system's business.
                    if c.kind != .delete, !ext.isVisible(c.path) { continue }
                    switch c.kind {
                    case .delete:
                        deleted.append(NSFileProviderItemIdentifier(c.id))
                        await ext.index.remove(path: c.path)
                    case .upsert, .move:
                        if let e = c.entry {
                            if let old = c.oldPath { await ext.index.move(from: old, to: e.path) }
                            // 1.5.2: only items the system knows, or whose folder it has listed:
                            // reporting every file that changes anywhere on the NAS (downloads in
                            // progress…) made the index grow without bound. Unknown items show up
                            // when their folder is opened.
                            let parent = GatewayPath.parent(e.path)
                            let known = await ext.index.knows(id: c.id)
                            let parentListed = parent == "/" ? true : await ext.index.hasListing(parent)
                            guard known || parentListed else { continue }
                            updated.append(await ext.makeItem(e))
                        } else {
                            deleted.append(NSFileProviderItemIdentifier(c.id))
                        }
                    }
                }
                // Build 45: what the recent-folders watcher found on the NAS since the last pass.
                let (wu, wd) = await ext.takePendingChanges()
                for e in wu { updated.append(await ext.makeItem(e)) }
                deleted += wd
                deleted += await ext.index.takeRetired()
                if !updated.isEmpty { observer.didUpdate(updated) }
                if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted) }
                observer.finishEnumeratingChanges(upTo: Self.anchor(seq: page.seq), moreComing: page.truncated)
            } catch { Diag.error("enumerate", "working set changes", error); observer.finishEnumeratingWithError(FileProviderExtension.mapError(error)) }
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
                let entries = ext.visibleEntries(root.entries, in: "/")
                deleted += await ext.index.vanishedIdentifiers(in: "/", current: entries.map(\.name))
                await ext.index.rememberListing("/", names: entries.map(\.name))
                for e in entries { updated.append(await ext.makeItem(e)) }
            }
            for f in page.files where ext.isVisible(f.path) { updated.append(await ext.makeItem(f)) }
            var relisted = 0
            for d in page.dirs where d != "/" && ext.isVisible(d) {
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
