import Foundation
import FileProvider
import UniformTypeIdentifiers
import UnraidGatewayKit
import os

let fpLog = Logger(subsystem: "com.sdimambro.unraid-drive", category: "fileprovider")

/// Replicated File Provider extension backed by unraid-gateway.
///
/// One instance per domain; the domain identifier is the server id stored by
/// the app, from which the gateway URL (shared defaults) and the API key
/// (shared Keychain) are resolved.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    let client: GatewayClient?
    let index: ItemIndex
    let tempDir: URL

    required init(domain: NSFileProviderDomain) {
        GatewayClient.component = "File Provider"
        self.domain = domain
        let serverID = domain.identifier.rawValue
        if let server = ServerStore().server(id: serverID), let c = GatewayClientFactory.client(for: server) {
            client = c
        } else {
            client = nil
            fpLog.error("no server config or api key for domain \(serverID, privacy: .public)")
        }
        index = ItemIndex(domainID: serverID)
        let mgr = NSFileProviderManager(for: domain)
        tempDir = (try? mgr?.temporaryDirectoryURL()) ?? FileManager.default.temporaryDirectory
        super.init()
    }

    func invalidate() {
        Task { await index.flush() }
    }

    // MARK: - Helpers

    /// Path for an identifier: from the local cache, or resolved through the gateway
    /// (gateway 0.5+ ids survive a reinstall even though the cache does not).
    func path(for identifier: NSFileProviderItemIdentifier) async -> String? {
        if identifier == .rootContainer { return "/" }
        if let p = await index.path(for: identifier) { return p }
        guard let client, let entry = try? await client.item(id: identifier.rawValue) else { return nil }
        await index.remember(id: identifier.rawValue, path: entry.path)
        return entry.path
    }

    /// The user's share selection, read fresh each time (it changes from the app while we run).
    func isVisible(_ path: String) -> Bool {
        ServerStore().server(id: domain.identifier.rawValue)?.isVisible(path: path) ?? true
    }

    /// Root listings only show the shares the user selected; hidden ones vanish like unmounted shares.
    func visibleEntries(_ entries: [FSEntry], in path: String) -> [FSEntry] {
        guard path == "/" else { return entries }
        return entries.filter { isVisible($0.path) }
    }

    /// Re-lists the root and reports shares that vanished (unmounted or hidden by the user) as
    /// deletions and the visible ones as updates, so a changed selection reaches the Files app /
    /// Finder even when no directory enumerator is active.
    func reconcileRoot(client: GatewayClient, updated: inout [NSFileProviderItem], deleted: inout [NSFileProviderItemIdentifier]) async {
        guard let root = try? await client.list("/") else { return }
        var shown: [FSEntry] = [], hidden: [FSEntry] = []
        for e in root.entries { if isVisible(e.path) { shown.append(e) } else { hidden.append(e) } }
        let gone = await index.vanishedIdentifiers(in: "/", current: shown.map(\.name))
        await index.rememberListing("/", names: shown.map(\.name))
        for e in shown { updated.append(await makeItem(e)) }
        // Shares the user hid are reported as deleted on every pass: idempotent for the system, and
        // it also repairs a location that still lists a share hidden before this pass ran.
        for e in hidden { deleted.append(await index.identifier(for: e)) }
        deleted += gone
        if !hidden.isEmpty || !gone.isEmpty {
            fpLog.notice("root: \(shown.count) shares shown, \(hidden.count) hidden by selection, \(gone.count) unmounted")
        }
    }

    /// Asks the system to enumerate the working set soon (deletions can only be reported there).
    func nudgeWorkingSet() {
        guard let mgr = NSFileProviderManager(for: domain) else { return }
        mgr.signalEnumerator(for: .workingSet) { _ in }
    }

    private func requireClient() throws -> GatewayClient {
        guard let client else { throw NSFileProviderError(.notAuthenticated) }
        return client
    }

    /// Maps gateway failures onto File Provider errors the system understands.
    static func mapError(_ error: Error) -> Error {
        if let e = error as? GatewayError {
            switch e {
            case .unauthorized, .locked: return NSFileProviderError(.notAuthenticated)
            case .notFound: return NSFileProviderError(.noSuchItem)
            case .conflict: return NSFileProviderError(.filenameCollision)
            case .network, .interceptedByProxy: return NSFileProviderError(.serverUnreachable)
            // Cloudflare answers 502/503/504 while the container restarts: transient, not a sync failure.
            case .http(let code, _) where (502...504).contains(code): return NSFileProviderError(.serverUnreachable)
            // Keep the gateway's explanation (folder, owner, mode, fix) next to the system's generic text.
            case .forbidden(let reason):
                return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                               userInfo: reason.isEmpty ? nil : [NSLocalizedFailureReasonErrorKey: reason])
            case .http(let code, _) where code == 507: return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
            default: return NSFileProviderError(.cannotSynchronize)
            }
        }
        if error is CancellationError { return NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
        return error
    }

    func makeItem(_ entry: FSEntry) async -> FileProviderItem {
        let id = await index.identifier(for: entry)
        let parent: NSFileProviderItemIdentifier
        if let pid = entry.parentID, !pid.isEmpty {
            parent = pid == gatewayRootID ? .rootContainer : NSFileProviderItemIdentifier(pid)
        } else {
            parent = await index.identifier(for: GatewayPath.parent(entry.path))
        }
        // Share permissions come from the last login (per-user gateways); unknown → writable.
        var readOnly = false
        if let client, let share = entry.path.split(separator: "/").first {
            if await client.sharePermissions == nil { _ = try? await client.login() }
            readOnly = await client.access(forShare: String(share)) == .readOnly
        }
        return FileProviderItem(entry: entry, identifier: id, parent: parent, readOnly: readOnly)
    }

    /// Wraps an async operation in the Progress the system expects.
    private func run(_ body: @escaping () async throws -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let task = Task {
            do { try await body() } catch { fpLog.error("operation failed: \(String(describing: error), privacy: .public)") }
            progress.completedUnitCount = 1
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - NSFileProviderReplicatedExtension

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        run {
            if identifier == .rootContainer { completionHandler(RootItem(), nil); return }
            if identifier == .trashContainer || identifier == .workingSet { completionHandler(nil, NSFileProviderError(.noSuchItem)); return }
            guard let path = await self.path(for: identifier), self.isVisible(path) else {
                // Unknown, or inside a share the user hid: to the system it no longer exists.
                completionHandler(nil, NSFileProviderError(.noSuchItem)); return
            }
            do {
                let entry = try await self.requireClient().stat(path)
                completionHandler(await self.makeItem(entry), nil)
            } catch {
                if case GatewayError.notFound = error { self.nudgeWorkingSet() }
                completionHandler(nil, Self.mapError(error))
            }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        run {
            guard let path = await self.path(for: itemIdentifier), self.isVisible(path) else { completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return }
            do {
                let client = try self.requireClient()
                let dest = self.tempDir.appendingPathComponent(UUID().uuidString)
                _ = try await client.download(path, to: dest)
                let entry = try await client.stat(path)
                // Give the local copy the server's timestamp so Files shows the real date.
                try? FileManager.default.setAttributes([.modificationDate: entry.mtime], ofItemAtPath: dest.path)
                self.log(path, .download, bytes: entry.size)
                completionHandler(dest, await self.makeItem(entry), nil)
            } catch { self.log(path, .download, error: error); completionHandler(nil, nil, Self.mapError(error)) }
        }
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        run {
            guard let parentPath = await self.path(for: itemTemplate.parentItemIdentifier) else {
                completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return
            }
            if parentPath == "/" {
                // Only mounted shares live at the root.
                completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)); return
            }
            let path = GatewayPath.join(parentPath, itemTemplate.filename)
            do {
                let client = try self.requireClient()
                let entry: FSEntry
                if itemTemplate.contentType == .folder {
                    do { entry = try await client.mkdir(path) }
                    catch GatewayError.conflict where options.contains(.mayAlreadyExist) { entry = try await client.stat(path) }
                } else {
                    let src = try url ?? self.emptyFile()
                    entry = try await client.upload(fileURL: src, to: path, overwrite: options.contains(.mayAlreadyExist),
                                                    mtime: itemTemplate.contentModificationDate ?? nil)
                }
                self.log(path, entry.isDirectory ? .folder : .create, bytes: entry.size)
                completionHandler(await self.makeItem(entry), [], false, nil)
            } catch {
                self.log(path, itemTemplate.contentType == .folder ? .folder : .create, error: error)
                // The parent is gone on the server (typically a share removed from the container):
                // let the working set delete it locally rather than retrying this item forever.
                if case GatewayError.notFound = error { self.nudgeWorkingSet() }
                completionHandler(nil, [], false, Self.mapError(error))
            }
        }
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        run {
            guard var path = await self.path(for: item.itemIdentifier) else { completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return }
            do {
                let client = try self.requireClient()
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    guard let newParent = await self.path(for: item.parentItemIdentifier) else { throw NSFileProviderError(.noSuchItem) }
                    let newPath = GatewayPath.join(newParent, item.filename)
                    if newPath != path {
                        _ = try await client.move(path, to: newPath, overwrite: false)
                        await self.index.move(from: path, to: newPath)
                        path = newPath
                        self.log(path, .move)
                    }
                }
                if changedFields.contains(.contents), let newContents {
                    let e = try await client.upload(fileURL: newContents, to: path, overwrite: true, mtime: item.contentModificationDate ?? nil)
                    self.log(path, .upload, bytes: e.size)
                } else if changedFields.contains(.contentModificationDate) {
                    // Metadata-only touch: nothing to store server-side; report current state.
                }
                let entry = try await client.stat(path)
                completionHandler(await self.makeItem(entry), [], false, nil)
            } catch { self.log(path, changedFields.contains(.contents) ? .upload : .move, error: error); completionHandler(nil, [], false, Self.mapError(error)) }
        }
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        run {
            guard let path = await self.path(for: identifier) else { completionHandler(nil); return }
            do {
                try await self.requireClient().delete(path, recursive: true)
                await self.index.remove(path: path)
                self.log(path, .delete)
                completionHandler(nil)
            } catch GatewayError.notFound {
                await self.index.remove(path: path)
                completionHandler(nil)
            } catch { self.log(path, .delete, error: error); completionHandler(Self.mapError(error)) }
        }
    }

    /// Records the operation for the app's sync-activity view (Mac menu bar).
    private func log(_ path: String, _ kind: ActivityEvent.Kind, bytes: Int64? = nil, error: Error? = nil) {
        ActivityLog.append(ActivityEvent(serverID: domain.identifier.rawValue, path: path, kind: kind, bytes: bytes,
                                         error: error.map { Self.describe(Self.mapError($0)) }))
    }

    /// Human-readable text for the activity log: the system message plus the gateway's reason when there is one.
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            return ns.localizedDescription + " — " + reason
        }
        return ns.localizedDescription
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        if containerItemIdentifier == .trashContainer { throw NSFileProviderError(.noSuchItem) }
        if containerItemIdentifier == .workingSet { return WorkingSetEnumerator(ext: self) }
        return DirectoryEnumerator(ext: self, container: containerItemIdentifier)
    }

    private func emptyFile() throws -> URL {
        let u = tempDir.appendingPathComponent(UUID().uuidString)
        try Data().write(to: u)
        return u
    }
}
