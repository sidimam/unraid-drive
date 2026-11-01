import Foundation
import FileProvider
import UnraidGatewayKit

/// Optional iCloud synchronisation of the app configuration.
///
/// Since 1.5.3 the profile is self-contained: name, URL, mode, shares **and** credentials (Unraid API
/// key, Cloudflare service token, Unraid user/password) travel together, so a profile restored on a
/// new or reinstalled device works right away. Until 1.5.2 the credentials depended on iCloud
/// Keychain carrying each Keychain item, which often did not happen ("the API key is missing").
/// - iCloud Key-Value Storage: `servers.v1` (the profiles with their credentials) and
///   `credentials.v1` (the credentials again, by profile id: older app versions rewrite `servers.v1`
///   without them and never touch this key).
/// - iCloud Drive › Unraid Drive › servers.json: the readable copy, **without** credentials.
/// Nothing leaves the device while the switch is off. The demo server is never synced.
@MainActor
final class CloudSync: ObservableObject {
    static let enabledKey = "icloudSync.enabled"
    private static let kvsKey = CloudKeys.servers
    private static let credentialsKey = CloudKeys.credentials

    @Published private(set) var enabled: Bool
    @Published private(set) var remoteServerCount: Int = 0
    @Published private(set) var lastSync: Date?
    @Published var lastError: String?
    /// State of `iCloud Drive › Unraid Drive › servers.json` for the Settings row.
    @Published private(set) var documentAvailable = false
    @Published private(set) var documentDate: Date?
    /// Container, synced folder (Developer ID build) or unavailable — the Settings row explains each.
    @Published private(set) var documentMode: CloudDocumentsStore.Mode = .unavailable

    private let kvs = NSUbiquitousKeyValueStore.default
    private let store = ServerStore()
    private var observer: NSObjectProtocol?
    private var docWatcher: CloudDocumentsWatcher?
    #if os(macOS)
    private var folderWatcher: FolderWatcher?
    #endif
    /// The last snapshot read from servers.json (merged with the Key-Value Store copy).
    private var documentServers: [ServerConfig] = []
    /// Called after a pull changed the local list (the model re-registers File Provider domains).
    var onRemoteChange: (() async -> Void)?

    init() {
        // Build 37: on by default for a new install — the configuration must always be recoverable
        // (servers.json in iCloud Drive + Key-Value Store, secrets in iCloud Keychain). The user can
        // still switch it off; the choice, once made, is kept.
        if AppGroup.defaults.object(forKey: Self.enabledKey) == nil { AppGroup.defaults.set(true, forKey: Self.enabledKey) }
        enabled = AppGroup.defaults.bool(forKey: Self.enabledKey)
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleExternalChange() }
        }
        kvs.synchronize()
        refreshRemoteCount()
        Task { await refreshDocument() }
        docWatcher = CloudDocumentsWatcher { [weak self] in Task { @MainActor in await self?.handleDocumentChange() } }
    }

    /// Servers currently stored in iCloud: the union of the Key-Value Store copy and servers.json,
    /// newest `modifiedAt` per id (either may be from another device or a previous install), each
    /// completed with the newest credentials found in either Key-Value Store key.
    var remoteServers: [ServerConfig] {
        var byID: [String: ServerConfig] = [:]
        let kvsList = kvs.data(forKey: Self.kvsKey).map(ServerStore.decode) ?? []
        for s in kvsList { byID[s.id] = s }
        for s in documentServers {
            if let e = byID[s.id], e.modifiedAt >= s.modifiedAt { continue }
            byID[s.id] = byID[s.id].map { s.mergingSecrets(from: $0) } ?? s
        }
        let creds = kvs.data(forKey: Self.credentialsKey).map(ProfileCredentials.decode) ?? [:]
        for (id, c) in creds { if let s = byID[id] { byID[id] = s.applying(c) } }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func refreshRemoteCount() { remoteServerCount = remoteServers.count }

    /// Re-reads servers.json from iCloud Drive (off the main thread) and updates the published state.
    func refreshDocument() async {
        let store = CloudDocumentsStore.shared
        let snap = await store.read()
        documentAvailable = await store.isAvailable
        documentDate = await store.modificationDate()
        documentMode = await store.mode
        documentServers = snap?.servers.filter { !$0.isDemo } ?? []
        refreshRemoteCount()
        #if os(macOS)
        if documentMode == .syncedFolder, folderWatcher == nil, let url = await store.fileURL() {
            folderWatcher = FolderWatcher(directory: url.deletingLastPathComponent()) { [weak self] in Task { @MainActor in await self?.handleDocumentChange() } }
        }
        #endif
    }

    private func handleDocumentChange() async {
        await refreshDocument()
        Diag.debug("icloud-drive", "servers.json changed in iCloud: \(documentServers.count) server(s)")
        guard enabled else { return }
        await pull()
    }

    // MARK: Switch

    func setEnabled(_ on: Bool) async {
        lastError = nil
        AppGroup.defaults.set(on, forKey: Self.enabledKey)
        enabled = on
        Diag.info("icloud", "sync \(on ? "enabled" : "disabled") by the user")
        if on {
            await pull()
            push()
        }
        // Turning sync off keeps the copy already in iCloud: it is the restore point of the other
        // devices and of the next reinstall. `removeCloudCopy()` deletes it on explicit request.
    }

    /// Deletes the profiles (and their credentials) from iCloud Key-Value Storage and servers.json.
    func removeCloudCopy() {
        kvs.removeObject(forKey: Self.kvsKey)
        kvs.removeObject(forKey: Self.credentialsKey)
        kvs.synchronize()
        documentServers = []
        refreshRemoteCount()
        Diag.info("icloud", "server list removed from iCloud by the user")
        Task { [weak self] in await CloudDocumentsStore.shared.remove(); await self?.refreshDocument() }
    }

    // MARK: Push / pull

    /// Mirrors the local list to iCloud (no-op when disabled).
    func push() {
        guard enabled else { return }
        let servers = store.all().filter { !$0.isDemo }
        // Never replace a populated cloud list with an empty one: an install that has not restored
        // yet (or a debug build without servers) must not erase everybody else's restore point.
        if servers.isEmpty, remoteServerCount > 0 {
            Diag.warning("icloud", "push skipped: local list empty while iCloud holds \(remoteServerCount) server(s)")
            return
        }
        if let data = ServerStore.encode(servers) {
            kvs.set(data, forKey: Self.kvsKey)
            // Credentials again on their own key, merged with what is there: a profile this device
            // has without credentials (still arriving) must not erase those another device saved.
            var creds = kvs.data(forKey: Self.credentialsKey).map(ProfileCredentials.decode) ?? [:]
            for (id, c) in ProfileCredentials.map(servers) where (creds[id]?.modifiedAt ?? .distantPast) <= (c.modifiedAt ?? .distantPast) || creds[id]?.apiKey == nil { creds[id] = c }
            creds = creds.filter { id, _ in servers.contains { $0.id == id } || remoteServers.contains { $0.id == id } }
            if let cd = ProfileCredentials.encode(creds) { kvs.set(cd, forKey: Self.credentialsKey) }
            kvs.synchronize()
            lastSync = Date()
            refreshRemoteCount()
            Diag.debug("icloud", "pushed \(servers.count) profile(s), \(servers.filter(\.hasCredentials).count) with credentials")
        }
        // The readable copy in iCloud Drive › Unraid Drive › servers.json: never the credentials.
        let readable = servers.map(\.withoutSecrets)
        Task { [weak self] in
            do { try await CloudDocumentsStore.shared.write(readable) } catch { await MainActor.run { self?.lastError = "iCloud Drive: \(error.localizedDescription)" } }
            await self?.refreshDocument()
        }
    }

    /// Merges the iCloud list into the local one: unknown ids are added, known ids take the
    /// newer `modifiedAt`; the credentials go their own way (newest set wins, a copy without
    /// credentials never erases them). Returns true when the local list changed.
    @discardableResult
    func pull() async -> Bool {
        await refreshDocument()
        let remote = remoteServers
        guard !remote.isEmpty else { return false }
        var local = store.all()
        var changed = false
        for r in remote where !r.isDemo {
            if let i = local.firstIndex(where: { $0.id == r.id }) {
                let merged = r.modifiedAt > local[i].modifiedAt ? r.mergingSecrets(from: local[i]) : local[i].mergingSecrets(from: r)
                if merged != local[i] {
                    if merged.apiKey != local[i].apiKey || merged.secretsModifiedAt != local[i].secretsModifiedAt { Diag.info("icloud", "\(merged.name): credentials updated from iCloud") }
                    local[i] = merged; changed = true
                }
            } else {
                local.append(r); changed = true
            }
        }
        if changed {
            store.save(local.sorted { $0.createdAt < $1.createdAt })
            lastSync = Date()
            Diag.info("icloud", "pulled \(remote.count) server(s) from iCloud, local list changed")
            await onRemoteChange?()
        }
        refreshRemoteCount()
        return changed
    }

    /// Explicit restore, offered when iCloud has servers and the device has none (fresh install).
    func restoreFromCloud() async {
        AppGroup.defaults.set(true, forKey: Self.enabledKey)
        enabled = true
        Diag.info("icloud", "restore requested (\(remoteServerCount) server(s) in iCloud)")
        await pull()
        let list = store.all().filter { !$0.isDemo }
        Diag.info("icloud", "restored \(list.count) profile(s), \(list.filter(\.hasCredentials).count) with credentials")
    }

    private func handleExternalChange() async {
        refreshRemoteCount()
        // A fresh install may only now learn the id iCloud remembers for this hardware.
        DeviceIdentity.reconcileWithCloud()
        Diag.debug("icloud", "external change: \(remoteServerCount) server(s) in iCloud, sync \(enabled ? "on" : "off")")
        guard enabled else { return }
        await pull()
    }

    /// True when a restore should be suggested: nothing local, something in iCloud.
    func shouldOfferRestore(localServers: [ServerConfig]) -> Bool {
        localServers.filter { !$0.isDemo }.isEmpty && remoteServerCount > 0
    }
}
