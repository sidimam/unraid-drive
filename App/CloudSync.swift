import Foundation
import FileProvider
import UnraidGatewayKit

/// Optional iCloud synchronisation of the app configuration.
///
/// - The server list (names, URLs, connection modes) goes to iCloud Key-Value Storage.
/// - Secrets (API keys, Cloudflare service tokens) go to iCloud Keychain, end-to-end encrypted,
///   by marking the Keychain items synchronizable.
/// Nothing leaves the device while the switch is off. The demo server is never synced.
@MainActor
final class CloudSync: ObservableObject {
    static let enabledKey = "icloudSync.enabled"
    private static let kvsKey = CloudKeys.servers

    @Published private(set) var enabled: Bool
    @Published private(set) var remoteServerCount: Int = 0
    @Published private(set) var lastSync: Date?
    @Published var lastError: String?
    /// State of `iCloud Drive › Unraid Drive › servers.json` for the Settings row.
    @Published private(set) var documentAvailable = false
    @Published private(set) var documentDate: Date?

    private let kvs = NSUbiquitousKeyValueStore.default
    private let store = ServerStore()
    private let keychain = KeychainStore()
    private var observer: NSObjectProtocol?
    private var docWatcher: CloudDocumentsWatcher?
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
    /// newest `modifiedAt` per id (either may be from another device or a previous install).
    var remoteServers: [ServerConfig] {
        var byID: [String: ServerConfig] = [:]
        if let data = kvs.data(forKey: Self.kvsKey) { for s in ServerStore.decode(data) { byID[s.id] = s } }
        for s in documentServers { if let e = byID[s.id], e.modifiedAt >= s.modifiedAt { continue }; byID[s.id] = s }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func refreshRemoteCount() { remoteServerCount = remoteServers.count }

    /// Re-reads servers.json from iCloud Drive (off the main thread) and updates the published state.
    func refreshDocument() async {
        let store = CloudDocumentsStore.shared
        let snap = await store.read()
        documentAvailable = await store.isAvailable
        documentDate = await store.modificationDate()
        documentServers = snap?.servers.filter { !$0.isDemo } ?? []
        refreshRemoteCount()
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
        let local = store.all().filter { !$0.isDemo }
        do {
            for s in local { try keychain.setSynchronizable(on, for: s.id) }
        } catch { lastError = "Keychain: \(error.localizedDescription)"; Diag.error("icloud", "keychain flag change", error) }
        if on {
            await pull()
            push()
        }
        // Turning sync off keeps the copy already in iCloud: it is the restore point of the other
        // devices and of the next reinstall. `removeCloudCopy()` deletes it on explicit request.
    }

    /// Deletes the server list from iCloud Key-Value Storage (the secrets in iCloud Keychain are
    /// untouched: they follow each device's own synchronizable flag).
    func removeCloudCopy() {
        kvs.removeObject(forKey: Self.kvsKey)
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
            kvs.synchronize()
            lastSync = Date()
            refreshRemoteCount()
            Diag.debug("icloud", "pushed \(servers.count) server(s)")
        }
        // The readable copy in iCloud Drive › Unraid Drive › servers.json.
        Task { [weak self] in
            do { try await CloudDocumentsStore.shared.write(servers) } catch { await MainActor.run { self?.lastError = "iCloud Drive: \(error.localizedDescription)" } }
            await self?.refreshDocument()
        }
    }

    /// Merges the iCloud list into the local one: unknown ids are added, known ids take the
    /// newer `modifiedAt`. Returns true when the local list changed.
    @discardableResult
    func pull() async -> Bool {
        await refreshDocument()
        let remote = remoteServers
        guard !remote.isEmpty else { return false }
        var local = store.all()
        var changed = false
        for r in remote where !r.isDemo {
            if let i = local.firstIndex(where: { $0.id == r.id }) {
                if r.modifiedAt > local[i].modifiedAt { local[i] = r; changed = true }
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
        // Secrets arrive through iCloud Keychain on their own; mark local copies synchronizable
        // (non-destructive: whatever has not arrived yet is left alone).
        for s in store.all() where !s.isDemo {
            do { try keychain.setSynchronizable(true, for: s.id) } catch { Diag.error("icloud", "restore keychain flag \(s.id.prefix(8))", error) }
        }
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
