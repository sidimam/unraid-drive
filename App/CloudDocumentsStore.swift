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

    /// How servers.json is reached.
    /// - `container`: the app's own iCloud Drive container (App Store / TestFlight / development builds).
    /// - `syncedFolder`: the Developer ID (Homebrew) build on the Mac. Apple grants iCloud Drive containers
    ///   only to App Store apps, so `url(forUbiquityContainerIdentifier:)` is nil there; iCloud Drive still
    ///   syncs the container written by the other devices to `~/Library/Mobile Documents/iCloud~com~sdimambro~unraid-drive`,
    ///   and that build reads and writes the folder directly (sandbox exception in UnraidDrive-macOS-DeveloperID.entitlements).
    ///   The folder exists only after another device has saved the list once.
    /// - `unavailable`: iCloud Drive off, or nothing to fall back to.
    enum Mode: Sendable { case container, syncedFolder, unavailable }
    private(set) var mode: Mode = .unavailable
    private var ubiquityDocs: URL??
    private var warned = false

    /// `…/Documents/servers.json`, or nil when iCloud Drive is not available.
    func fileURL() -> URL? {
        if ubiquityDocs == nil {
            // `url(forUbiquityContainerIdentifier:)` may take a moment the first time: this actor is
            // never called from the main thread synchronously. The answer does not change while the app runs.
            ubiquityDocs = .some(FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)?.appendingPathComponent("Documents", isDirectory: true))
        }
        if case .some(.some(let docs)) = ubiquityDocs {
            mode = .container
            return file(in: docs)
        }
        #if os(macOS)
        // Re-checked every time: the synced folder appears as soon as iCloud Drive brings it down.
        if let folder = Self.syncedContainerFolder() {
            if mode != .syncedFolder { Diag.info("icloud-drive", "container not granted to this build; using the folder synced by iCloud Drive: \(folder.path)") }
            mode = .syncedFolder
            return file(in: folder.appendingPathComponent("Documents", isDirectory: true))
        }
        #endif
        mode = .unavailable
        if !warned {
            warned = true
            Diag.warning("icloud-drive", "container \(Self.containerID) not available (iCloud Drive off, or this build is not granted a container: Developer ID builds get one only after another device saved servers.json)")
        }
        return nil
    }

    private func file(in docs: URL) -> URL {
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs.appendingPathComponent(Self.fileName)
    }

    #if os(macOS)
    /// `~/Library/Mobile Documents/iCloud~com~sdimambro~unraid-drive` (the real home, not the sandbox
    /// container) when iCloud Drive has already synced it to this Mac.
    nonisolated static func syncedContainerFolder() -> URL? {
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir.map({ String(cString: $0) }) else { return nil }
        let folder = URL(fileURLWithPath: home).appendingPathComponent("Library/Mobile Documents/" + Self.containerID.replacingOccurrences(of: ".", with: "~"), isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue ? folder : nil
    }
    #endif

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

#if os(macOS)
/// Watches the synced iCloud Drive folder of the Developer ID build (outside the ubiquity scope,
/// `NSMetadataQuery` sees nothing there): a change in the Documents folder triggers a re-read.
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(directory: URL, onChange: @escaping () -> Void) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem { onChange() }
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)   // iCloud writes arrive in bursts
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
#endif
