import Foundation
import UnraidGatewayKit

/// The server configuration as a plain JSON file in the user's iCloud Drive
/// (`iCloud Drive › Unraid Drive › servers.json`), next to the Key-Value Store copy.
///
/// Why a file: it is visible, readable and versioned by iCloud, survives every reinstall and any
/// device, and can be inspected or restored by hand. Secrets are never in it — they stay in iCloud
/// Keychain (the *Passwords* of the Apple account) as synchronizable Keychain items.
///
/// The container is `iCloud.com.sdimambro.unraid-drive`; when the account has iCloud Drive off, or
/// the build was signed without the container, `url` is nil and everything here is a no-op that
/// says so in the log. tvOS has no iCloud Drive documents and keeps using the Key-Value Store.
actor CloudDocumentsStore {
    static let shared = CloudDocumentsStore()
    static let containerID = "iCloud.com.sdimambro.unraid-drive"
    static let fileName = "servers.json"

    /// What the file holds. `servers` never carry secrets (`ServerConfig` has none).
    struct Snapshot: Codable {
        var schema: Int = 1
        var updatedAt: Date
        var updatedBy: String
        var servers: [ServerConfig]
    }

    private var cachedURL: URL??

    /// `…/Documents/servers.json` inside the container, or nil when iCloud Drive is not available.
    func fileURL() -> URL? {
        if let cachedURL { return cachedURL }
        // `url(forUbiquityContainerIdentifier:)` may take a moment the first time: this actor is
        // never called from the main thread synchronously.
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) else {
            Diag.warning("icloud-drive", "container \(Self.containerID) not available (iCloud Drive off, or the app was signed without it)")
            cachedURL = .some(nil)
            return nil
        }
        let docs = base.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        let url = docs.appendingPathComponent(Self.fileName)
        cachedURL = .some(url)
        return url
    }

    var isAvailable: Bool { fileURL() != nil }

    /// Writes the list (demo excluded by the caller) atomically through file coordination.
    func write(_ servers: [ServerConfig]) throws {
        guard let url = fileURL() else { return }
        let snap = Snapshot(updatedAt: Date(), updatedBy: GatewayClient.clientDescription, servers: servers)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(snap)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? (writeError as NSError?) { Diag.error("icloud-drive", "write servers.json", e); throw e }
        Diag.info("icloud-drive", "servers.json written (\(servers.count) server(s), \(data.count) B)")
    }

    /// Reads the file; a not-yet-downloaded item is fetched first (coordinated reads wait for it).
    /// Returns nil when there is no file (nothing ever saved) or iCloud Drive is unavailable.
    func read() -> Snapshot? {
        guard let url = fileURL() else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Placeholder (`.servers.json.icloud`) → ask for the download and let the coordinated read wait.
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(Self.fileName).icloud")
            guard fm.fileExists(atPath: placeholder.path) else { Diag.debug("icloud-drive", "no servers.json in iCloud Drive yet"); return nil }
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
        var coordError: NSError?
        var result: Snapshot?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do {
                let data = try Data(contentsOf: u)
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                result = try dec.decode(Snapshot.self, from: data)
            } catch { readError = error }
        }
        if let e = coordError ?? (readError as NSError?) { Diag.error("icloud-drive", "read servers.json", e); return nil }
        if let result { Diag.debug("icloud-drive", "servers.json read: \(result.servers.count) server(s), updated \(result.updatedAt.formatted(.iso8601)) by \(result.updatedBy)") }
        return result
    }

    /// Deletes the file (explicit user request only).
    func remove() {
        guard let url = fileURL() else { return }
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { u in
            try? FileManager.default.removeItem(at: u)
        }
        Diag.info("icloud-drive", "servers.json removed from iCloud Drive")
    }

    /// Last modification of the file, for the Settings row.
    func modificationDate() -> Date? {
        guard let url = fileURL(), let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }
}

/// Tells `CloudSync` when servers.json changes in iCloud (another device wrote it).
@MainActor
final class CloudDocumentsWatcher {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, CloudDocumentsStore.fileName)
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                self?.query.disableUpdates()
                self?.onChange()
                self?.query.enableUpdates()
            })
        }
        query.start()
    }

    deinit { query.stop() }
}
