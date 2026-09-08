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
                await ext.index.rememberListing(path, names: listing.entries.map(\.name))
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
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
                let dirChanged = page.dirs.contains(path)
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

/// The working set: everything the system has materialized. We report changes
/// across the whole tree using the paginated change feed; deletions are
/// detected by re-listing changed directories we have seen before.
final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    private let ext: FileProviderExtension
    init(ext: FileProviderExtension) { self.ext = ext }
    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            guard let a = SyncAnchor(anchor) else { observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired)); return }
            do {
                guard let client = ext.client else { throw NSFileProviderError(.notAuthenticated) }
                let page = try await client.changes("/", since: a.cursor, after: a.after, cursor: a.after == nil ? nil : a.cursor, limit: 5000)
                var updated: [NSFileProviderItem] = []
                var deleted: [NSFileProviderItemIdentifier] = []
                for f in page.files { updated.append(await ext.makeItem(f)) }
                var relisted = 0
                for d in page.dirs where d != "/" {
                    // Only directories we have listed before can have vanished children we know about.
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
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(SyncAnchor.now.raw)
    }
}
