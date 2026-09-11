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

    private let kvs = NSUbiquitousKeyValueStore.default
    private let store = ServerStore()
    private let keychain = KeychainStore()
    private var observer: NSObjectProtocol?
    /// Called after a pull changed the local list (the model re-registers File Provider domains).
    var onRemoteChange: (() async -> Void)?

    init() {
        enabled = AppGroup.defaults.bool(forKey: Self.enabledKey)
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleExternalChange() }
        }
        kvs.synchronize()
        refreshRemoteCount()
    }

    /// Servers currently stored in iCloud (may be from another device or a previous install).
    var remoteServers: [ServerConfig] {
        guard let data = kvs.data(forKey: Self.kvsKey) else { return [] }
        return ServerStore.decode(data)
    }

    private func refreshRemoteCount() { remoteServerCount = remoteServers.count }

    // MARK: Switch

    func setEnabled(_ on: Bool) async {
        lastError = nil
        AppGroup.defaults.set(on, forKey: Self.enabledKey)
        enabled = on
        let local = store.all().filter { !$0.isDemo }
        do {
            for s in local { try keychain.setSynchronizable(on, for: s.id) }
        } catch { lastError = "Keychain: \(error.localizedDescription)" }
        if on {
            await pull()
            push()
        } else {
            kvs.removeObject(forKey: Self.kvsKey)
            kvs.synchronize()
            refreshRemoteCount()
        }
    }

    // MARK: Push / pull

    /// Mirrors the local list to iCloud (no-op when disabled).
    func push() {
        guard enabled else { return }
        let servers = store.all().filter { !$0.isDemo }
        if let data = ServerStore.encode(servers) {
            kvs.set(data, forKey: Self.kvsKey)
            kvs.synchronize()
            lastSync = Date()
            refreshRemoteCount()
        }
    }

    /// Merges the iCloud list into the local one: unknown ids are added, known ids take the
    /// newer `modifiedAt`. Returns true when the local list changed.
    @discardableResult
    func pull() async -> Bool {
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
            await onRemoteChange?()
        }
        refreshRemoteCount()
        return changed
    }

    /// Explicit restore, offered when iCloud has servers and the device has none (fresh install).
    func restoreFromCloud() async {
        AppGroup.defaults.set(true, forKey: Self.enabledKey)
        enabled = true
        await pull()
        // Secrets arrive through iCloud Keychain on their own; mark local copies synchronizable.
        for s in store.all() where !s.isDemo { try? keychain.setSynchronizable(true, for: s.id) }
    }

    private func handleExternalChange() async {
        refreshRemoteCount()
        guard enabled else { return }
        await pull()
    }

    /// True when a restore should be suggested: nothing local, something in iCloud.
    func shouldOfferRestore(localServers: [ServerConfig]) -> Bool {
        localServers.filter { !$0.isDemo }.isEmpty && remoteServerCount > 0
    }
}
