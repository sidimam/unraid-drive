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
            case .network: return NSFileProviderError(.serverUnreachable)
            case .forbidden: return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            case .http(let code, _) where code == 507: return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
            default: return NSFileProviderError(.cannotSynchronize)
            }
        }
        if error is CancellationError { return NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
        return error
    }

    func makeItem(_ entry: FSEntry) async -> FileProviderItem {
        let id = await index.identifier(for: entry.path)
        let parent = await index.identifier(for: GatewayPath.parent(entry.path))
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
            guard let path = await self.index.path(for: identifier) else { completionHandler(nil, NSFileProviderError(.noSuchItem)); return }
            do {
                let entry = try await self.requireClient().stat(path)
                completionHandler(await self.makeItem(entry), nil)
            } catch { completionHandler(nil, Self.mapError(error)) }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        run {
            guard let path = await self.index.path(for: itemIdentifier) else { completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return }
            do {
                let client = try self.requireClient()
                let dest = self.tempDir.appendingPathComponent(UUID().uuidString)
                _ = try await client.download(path, to: dest)
                let entry = try await client.stat(path)
                // Give the local copy the server's timestamp so Files shows the real date.
                try? FileManager.default.setAttributes([.modificationDate: entry.mtime], ofItemAtPath: dest.path)
                completionHandler(dest, await self.makeItem(entry), nil)
            } catch { completionHandler(nil, nil, Self.mapError(error)) }
        }
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        run {
            guard let parentPath = await self.index.path(for: itemTemplate.parentItemIdentifier) else {
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
                completionHandler(await self.makeItem(entry), [], false, nil)
            } catch { completionHandler(nil, [], false, Self.mapError(error)) }
        }
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        run {
            guard var path = await self.index.path(for: item.itemIdentifier) else { completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return }
            do {
                let client = try self.requireClient()
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    guard let newParent = await self.index.path(for: item.parentItemIdentifier) else { throw NSFileProviderError(.noSuchItem) }
                    let newPath = GatewayPath.join(newParent, item.filename)
                    if newPath != path {
                        _ = try await client.move(path, to: newPath, overwrite: false)
                        await self.index.move(from: path, to: newPath)
                        path = newPath
                    }
                }
                if changedFields.contains(.contents), let newContents {
                    _ = try await client.upload(fileURL: newContents, to: path, overwrite: true, mtime: item.contentModificationDate ?? nil)
                } else if changedFields.contains(.contentModificationDate) {
                    // Metadata-only touch: nothing to store server-side; report current state.
                }
                let entry = try await client.stat(path)
                completionHandler(await self.makeItem(entry), [], false, nil)
            } catch { completionHandler(nil, [], false, Self.mapError(error)) }
        }
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        run {
            guard let path = await self.index.path(for: identifier) else { completionHandler(nil); return }
            do {
                try await self.requireClient().delete(path, recursive: true)
                await self.index.remove(path: path)
                completionHandler(nil)
            } catch GatewayError.notFound {
                await self.index.remove(path: path)
                completionHandler(nil)
            } catch { completionHandler(Self.mapError(error)) }
        }
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
