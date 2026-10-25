import Foundation
import FileProvider
import UnraidGatewayKit
import os

/// Owns the server list and keeps File Provider domains in sync with it.
@MainActor
final class ServersModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    private let store = ServerStore()
    private let keychain = KeychainStore()
    let cloud = CloudSync()
    /// The profile the app opens on (build 42: the launch lands in its folders). Persisted in the app group.
    @Published private(set) var current: ServerConfig?
    private static let currentKey = "servers.current"
    /// One-glance health per server, derived from the dashboard; refreshed when the explorer root or a
    /// profile page appears.
    @Published private(set) var health: [String: ServerHealth] = [:]

    init() {
        reload()
        cloud.onRemoteChange = { [weak self] in await self?.reloadAndRegisterDomains() }
        if cloud.enabled { Task { await cloud.pull() } }
        Task { await maintainLocationsIfNeeded() }
        #if DEBUG
        // Launch-argument seeding runs here (not in a view): on the Mac the window may never appear.
        Task { await seedFromLaunchArguments() }
        #endif
    }

    /// After servers arrived from iCloud: reload and make sure each has a Files app location.
    func reloadAndRegisterDomains() async {
        reload()
        do {
            let existing = try await NSFileProviderManager.domains().map(\.identifier.rawValue)
            for s in servers where !existing.contains(s.id) {
                do { try await FileProviderDomains.add(s); Diag.info("location", "\(s.name): location registered") }
                catch { Diag.error("location", "\(s.name): register", error) }
            }
        } catch { Diag.error("location", "listing locations", error) }
        await maintainLocationsIfNeeded()
    }

    /// Restore from iCloud in one go: merge the list, register the locations and sign in on every
    /// server with `register: true`, so this installation is known to each gateway (the Settings
    /// and server-list buttons used to skip the registration step).
    func restoreFromCloudAndRegister() async {
        await cloud.restoreFromCloud()
        await reloadAndRegisterDomains()
        await registerRestoredDevices()
    }

    /// The system keeps a Files location's database across an uninstall when the same server comes
    /// back (iCloud restore), but the extension's item index, which maps its identifiers to paths,
    /// does not survive; an app update can also change what the extension reports. So, once per
    /// build (first install and every upgrade), each location is **checked and rebuilt
    /// automatically**: the gateway is contacted with the stored credentials, then the location is
    /// removed and registered again so the Files app / Finder starts from a clean database, and
    /// finally nudged. Nothing to do by hand: the server page shows when it last happened. If the
    /// gateway cannot be reached (or the credentials are still arriving from iCloud Keychain) the
    /// pass is retried the next time the app becomes active.
    static let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"

    struct LocationMaintenance: Codable, Equatable {
        var build: String
        var date: Date
        var gatewayOK: Bool
        var detail: String
        /// Build 37+: whether the Files/Finder location really exists after the pass (nil for
        /// records written by older builds). Until build 36 a pass counted as done as soon as the
        /// gateway answered, even when the location could not be registered again — which then
        /// never got retried.
        var locationOK: Bool?
        /// True when the pass ended in a state that only the user can fix (extension switched off).
        var needsUserAction: Bool?
        var done: Bool { gatewayOK && (locationOK ?? true) }
    }
    /// Per server id: the outcome of the last automatic pass (also persisted in the app group).
    @Published private(set) var maintenance: [String: LocationMaintenance] = [:]
    private static func maintenanceKey(_ id: String) -> String { "fp.maintenance." + id }
    private var maintaining = false

    func storedMaintenance(_ id: String) -> LocationMaintenance? {
        guard let d = AppGroup.defaults.data(forKey: Self.maintenanceKey(id)) else { return nil }
        return try? JSONDecoder().decode(LocationMaintenance.self, from: d)
    }
    private func record(_ m: LocationMaintenance, for id: String) {
        maintenance[id] = m
        if let d = try? JSONEncoder().encode(m) { AppGroup.defaults.set(d, forKey: Self.maintenanceKey(id)) }
    }

    /// Runs the automatic pass for every server that has not completed it on this build.
    /// `force` repeats it even when already done (e.g. "Check now" on the server page).
    func maintainLocationsIfNeeded(force: Bool = false, only: ServerConfig? = nil) async {
        guard !maintaining else { return }
        maintaining = true; defer { maintaining = false }
        for s in servers where !s.isDemo && (only == nil || only?.id == s.id) {
            let stored = storedMaintenance(s.id)
            if maintenance[s.id] == nil, let stored { maintenance[s.id] = stored }
            if !force, let stored, stored.build == Self.currentBuild, stored.done { continue }
            // 1. Connection check with the stored credentials.
            guard let c = client(for: s) else {
                Diag.warning("location", "\(s.name): maintenance skipped, credentials not readable yet")
                record(LocationMaintenance(build: Self.currentBuild, date: Date(), gatewayOK: false, detail: String(localized: "credentials not available yet")), for: s.id)
                continue
            }
            var gatewayOK = false
            var version = ""
            do {
                let h = try await c.health()
                _ = try await c.list("/")
                gatewayOK = true
                version = h.version ?? ""
                Diag.info("location", "\(s.name): gateway \(version) reachable, rebuilding the location (build \(Self.currentBuild))")
                // 2. Is the extension available at all? `domains()` throws `providerNotFound` when it
                //    is switched off: leave the location alone and say so (removing it now would
                //    not be undoable until the user flips the switch).
                _ = try await NSFileProviderManager.domains()
                // 3. Rebuild the location and verify it is really there, 4. nudge it.
                try await FileProviderDomains.rebuild(s)
                let present = try await NSFileProviderManager.domains().contains { $0.identifier.rawValue == s.id }
                guard present else { throw LocationError.missingAfterRebuild }
                await FileProviderDomains.signal(s)
                AppGroup.defaults.set(true, forKey: "fp.rebuilt.g\(Self.iconGeneration)." + s.id)
                record(LocationMaintenance(build: Self.currentBuild, date: Date(), gatewayOK: true, detail: String(localized: "gateway \(version)"), locationOK: true, needsUserAction: false), for: s.id)
                Diag.info("location", "\(s.name): location registered and checked")
            } catch {
                Diag.error("location", "\(s.name): maintenance failed (gateway \(gatewayOK ? "ok" : "unreachable"))", error)
                let detail = gatewayOK ? LocationErrorText.describe(error) : error.localizedDescription
                record(LocationMaintenance(build: Self.currentBuild, date: Date(), gatewayOK: gatewayOK, detail: detail, locationOK: gatewayOK ? false : nil, needsUserAction: gatewayOK ? LocationErrorText.needsUserAction(error) : false), for: s.id)
            }
        }
    }

    enum LocationError: LocalizedError {
        case missingAfterRebuild
        var errorDescription: String? { String(localized: "The location could not be registered again. Try once more; if it keeps failing, restart the device.") }
    }

    /// Bump when the app icon changes: the Files app shows the icon it saw when the location was
    /// registered (the per-build pass above re-registers it anyway).
    static let iconGeneration = 2

    /// First contact with a gateway that hands out stable ids (0.5+): rebuild the Files location
    /// once so items switch from local identifiers to server ids without duplicates.
    func adoptServerIDsIfNeeded(_ server: ServerConfig, entries: [FSEntry]) async {
        guard !server.isDemo, entries.contains(where: { $0.itemID != nil }) else { return }
        let key = "fp.serverIDs." + server.id
        guard !AppGroup.defaults.bool(forKey: key) else { return }
        do { try await FileProviderDomains.rebuild(server) } catch { Diag.error("location", "\(server.name): rebuild for server ids", error); return }
        AppGroup.defaults.set(true, forKey: key)
    }

    /// Explicit rebuild from the UI (discards local changes not yet uploaded).
    func rebuildDomain(_ server: ServerConfig) async {
        do { try await FileProviderDomains.rebuild(server) } catch { Diag.error("location", "\(server.name): manual rebuild", error); return }
        AppGroup.defaults.set(true, forKey: "fp.rebuilt.g\(Self.iconGeneration)." + server.id)
    }

    func reload() { servers = store.all(); syncCurrent() }

    /// Keeps `current` pointing at an existing profile: the remembered one, else the first real server.
    private func syncCurrent() {
        let id = AppGroup.defaults.string(forKey: Self.currentKey)
        current = servers.first { $0.id == id } ?? servers.first { !$0.isDemo } ?? servers.first
    }

    /// Makes a profile the one the explorer opens on.
    func select(_ server: ServerConfig) {
        AppGroup.defaults.set(server.id, forKey: Self.currentKey)
        syncCurrent()
        Diag.info("servers", "current profile → \(server.name)")
    }

    func client(for server: ServerConfig) -> GatewayClient? {
        GatewayClientFactory.client(for: server, keychain: keychain)
    }

    /// Health for the status dot (rule of 13/10/2026: only what concerns Unraid Drive and the gateway).
    /// Red: gateway unreachable or credentials refused, Files/Finder location that needs the user,
    /// gateway errors (no share mounted). Yellow: gateway warnings (unwritable share, /config, user
    /// auth), location check pending, failed uploads/downloads in the last 24 h, device not
    /// registered yet. Unraid's own state is never part of it. The demo is always fine.
    func refreshHealth(_ server: ServerConfig) async {
        if server.isDemo { health[server.id] = .fine; return }
        guard let c = client(for: server) else {
            health[server.id] = ServerHealth(level: .error, issues: [.init(.error, .credentials, String(localized: "Credentials missing from the Keychain: sign in again."), action: .signIn)])
            return
        }
        var issues: [ServerHealth.Issue] = []
        do {
            _ = try await c.health()
            if let g = try? await c.gatewayHealth() { issues += g.issues }
        } catch {
            health[server.id] = .unreachable(error.localizedDescription)
            return
        }
        // Files / Finder location: the automatic pass and its outcome.
        if let m = maintenance[server.id] ?? storedMaintenance(server.id) {
            if m.needsUserAction == true {
                issues.append(.init(.error, .location, m.detail, action: .openSystemSettings))
            } else if !m.done {
                issues.append(.init(.warning, .location, String(localized: "Files/Finder location check pending: \(m.detail)"), action: .checkLocation))
            }
        } else {
            issues.append(.init(.warning, .location, String(localized: "Files/Finder location not checked yet on this build."), action: .checkLocation))
        }
        // Transfers of the last 24 hours that failed (extension's activity log).
        let dayAgo = Date().addingTimeInterval(-86_400)
        let failed = ActivityLog.recent().filter { $0.serverID == server.id && $0.failed && $0.date > dayAgo }
        if !failed.isEmpty {
            issues.append(.init(.warning, .transfers, String(localized: "\(failed.count) failed transfer(s) in the last 24 hours (last: \(failed[0].name))"), action: .openDiagnostics))
        }
        // Sync pairs (1.5): a pair paused on the gateway or whose last run failed / had problems.
        for p in SyncStore.pairs(for: server.id) {
            if let by = p.pausedByGateway {
                issues.append(.init(.warning, .sync, String(localized: "Sync \(p.localLabel) paused on the gateway by \(by)."), action: .openSync))
            } else if p.enabled, let r = p.lastRun {
                if r.status == .failed { issues.append(.init(.error, .sync, String(localized: "Sync \(p.localLabel) failed: \(r.error ?? "")"), action: .openSync)) }
                else if r.status == .partial { issues.append(.init(.warning, .sync, String(localized: "Sync \(p.localLabel): \(r.conflicts) conflicts, \(r.errors) errors at the last run."), action: .openSync)) }
            }
        }
        // Device registration (restore from iCloud still waiting for the secrets / failed).
        if let r = restoreRegistration[server.id] {
            switch r {
            case .waitingSecrets: issues.append(.init(.warning, .device, String(localized: "Device registration waiting for the credentials from iCloud Keychain."), action: .reRegister))
            case .failed(let why): issues.append(.init(.warning, .device, why, action: .reRegister))
            case .registered: break
            }
        }
        health[server.id] = .from(issues)
    }

    // MARK: Restore from iCloud → register this device again

    enum RestoreRegistration: Equatable {
        case waitingSecrets, registered, failed(String)
    }
    /// Per server id: how the re-registration on the gateway went after an iCloud restore.
    @Published private(set) var restoreRegistration: [String: RestoreRegistration] = [:]

    /// After `CloudSync.restoreFromCloud()`: sign in on every restored server with `register: true`,
    /// so this installation (new id, or the previous one recovered through iCloud) is registered on
    /// the gateway and the Files locations work right away. The secrets travel through iCloud
    /// Keychain and may arrive a little after the server list: keep trying for `timeout` seconds.
    func registerRestoredDevices(timeout: TimeInterval = 120) async {
        let targets = servers.filter { !$0.isDemo }
        for s in targets { restoreRegistration[s.id] = .waitingSecrets }
        var pending = Set(targets.map(\.id))
        let deadline = Date().addingTimeInterval(timeout)
        Diag.info("device", "registering this installation on \(targets.count) restored server(s)")
        while !pending.isEmpty, Date() < deadline {
            for s in targets where pending.contains(s.id) {
                guard let c = client(for: s) else { continue }     // credentials not here yet
                do {
                    _ = try await c.login(register: true)
                    restoreRegistration[s.id] = .registered
                    pending.remove(s.id)
                    await FileProviderDomains.signal(s)
                } catch {
                    // Wrong key / revoked device: final. Anything else (network, gateway restarting)
                    // is retried until the deadline instead of giving up on the first hiccup.
                    if (error as? GatewayError)?.isAuthFailure == true {
                        restoreRegistration[s.id] = .failed(error.localizedDescription)
                        pending.remove(s.id)
                    } else {
                        Diag.warning("device", "\(s.name): registration retry after: \(error.localizedDescription)")
                    }
                }
            }
            if !pending.isEmpty { try? await Task.sleep(for: .seconds(5)) }
        }
        for id in pending {
            restoreRegistration[id] = .failed(String(localized: "The credentials have not arrived from iCloud Keychain yet. Open the server and use Connect again."))
        }
    }

    var hasDemo: Bool { servers.contains { $0.isDemo } }

    /// Nudges every Files app location to re-check its server (used when the app comes to
    /// the foreground: iOS pauses a domain after a network error and waits for a signal).
    func signalAllDomains() async {
        for s in servers where !s.isDemo { await FileProviderDomains.signal(s) }
    }

    /// Gateway reachability + failed sync operations → local notifications (if allowed).
    func checkHealthAndAlerts() async {
        await HealthMonitor.check(servers) { [weak self] s in self?.client(for: s) }
        await ActivityAlerts.process { [weak self] id in self?.servers.first { $0.id == id }?.name }
    }

    /// Validates the key against the gateway, then persists the server and
    /// registers its File Provider domain so it shows up in the Files app.
    func add(name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?, user: (username: String, password: String)? = nil) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, username: user?.username, password: user?.password, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login(register: true)
        var server = ServerConfig(name: name, url: url, accessMode: cloudflare == nil ? .direct : .cloudflareAccess)
        server.username = user?.username
        try keychain.set(apiKey: apiKey, for: server.id, synchronizable: cloud.enabled)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id, synchronizable: cloud.enabled) }
        if let user { try keychain.set(username: user.username, password: user.password, for: server.id, synchronizable: cloud.enabled) }
        store.upsert(server)
        try await FileProviderDomains.add(server)
        reload()
        record(LocationMaintenance(build: Self.currentBuild, date: Date(), gatewayOK: true, detail: String(localized: "gateway \(login.version ?? "")")), for: server.id)
        cloud.push()
        return login
    }

    /// Re-validates and replaces the credentials (and mode/name/url) of an existing server,
    /// keeping its id so the Files app location survives.
    func update(_ server: ServerConfig, name: String, url: URL, apiKey: String, cloudflare: CloudflareServiceToken?, user: (username: String, password: String)? = nil) async throws -> LoginResponse {
        let client = GatewayClient(baseURL: url, apiKey: apiKey, username: user?.username, password: user?.password, extraHeaders: cloudflare?.headers ?? [:])
        let login = try await client.login(register: true)
        var updated = server
        updated.name = name; updated.url = url; updated.accessMode = cloudflare == nil ? .direct : .cloudflareAccess
        updated.username = user?.username
        // Overwrite only what was provided: the old code deleted every secret first, so a save that
        // failed half-way (or dropped a field) left the server without credentials.
        try keychain.set(apiKey: apiKey, for: server.id, synchronizable: cloud.enabled)
        if let cloudflare { try keychain.set(cloudflareToken: cloudflare, for: server.id, synchronizable: cloud.enabled) }
        if let user { try keychain.set(username: user.username, password: user.password, for: server.id, synchronizable: cloud.enabled) }
        else { keychain.removeUserCredentials(for: server.id) }
        Diag.info("servers", "updated \(updated.name) (\(updated.accessMode)) credentials rewritten")
        store.upsert(updated)
        cloud.push()
        if updated.name != server.name {
            // Domain display name is fixed at registration: re-register to rename it.
            try? await FileProviderDomains.remove(server)
            try? await FileProviderDomains.add(updated)
        } else {
            await FileProviderDomains.signal(updated)
        }
        reload()
        return login
    }

    /// Stores which shares to show for a server (nil = all), syncs it and tells the Files app /
    /// Finder location to re-read its root so hidden shares disappear and re-enabled ones return.
    func setSelectedShares(_ server: ServerConfig, _ shares: [String]?) async {
        guard var s = store.server(id: server.id) else {
            Logger(subsystem: "com.sdimambro.unraid-drive", category: "shares").error("setSelectedShares: server \(server.id, privacy: .public) not in store")
            return
        }
        Logger(subsystem: "com.sdimambro.unraid-drive", category: "shares").notice("setSelectedShares \(server.id, privacy: .public) → \(shares?.joined(separator: ",") ?? "all", privacy: .public)")
        s.selectedShares = shares
        s.modifiedAt = Date()
        store.upsert(s)
        reload()
        cloud.push()
        await FileProviderDomains.signal(s)
    }

    /// Current configuration of a server (views often hold a copy that predates a change).
    func current(_ server: ServerConfig) -> ServerConfig { servers.first { $0.id == server.id } ?? server }

    /// Adds the built-in demo server (no network, sample files).
    func addDemo() async {
        let server = ServerConfig.demo
        store.upsert(server)
        try? await FileProviderDomains.add(server)
        reload()
    }

    func remove(_ server: ServerConfig) async {
        Diag.info("servers", "removing \(server.name) at the user's request (location, secrets, config)")
        try? await FileProviderDomains.remove(server)
        keychain.remove(for: server.id)
        store.remove(id: server.id)
        reload()
        cloud.push()
    }
}

enum FileProviderDomains {
    static func domain(for server: ServerConfig) -> NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(rawValue: server.id), displayName: server.name)
    }
    static func add(_ server: ServerConfig) async throws {
        try await NSFileProviderManager.add(domain(for: server))
    }
    static func remove(_ server: ServerConfig) async throws {
        try await NSFileProviderManager.remove(domain(for: server))
    }
    /// Removes the location (and everything the system cached for it, including our item index)
    /// and registers it again, so the Files app rebuilds the tree from the gateway.
    /// Throws when the location could not be registered again (the caller records it and retries
    /// on the next activation, instead of believing everything went fine).
    static func rebuild(_ server: ServerConfig) async throws {
        do { try await remove(server) } catch { Diag.debug("location", "\(server.name): remove before rebuild: \(error.localizedDescription)") }
        if let dir = AppGroup.containerURL?.appendingPathComponent("FileProvider/\(server.id)", isDirectory: true) {
            try? FileManager.default.removeItem(at: dir)
        }
        var last: Error?
        for attempt in 0..<5 {
            do { try await add(server); return } catch {
                last = error
                Diag.warning("location", "\(server.name): add attempt \(attempt + 1) failed: \(error.localizedDescription)")
                try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
        }
        throw last ?? NSFileProviderError(.providerNotFound)
    }

    /// Asks the system to refresh the domain's root and working set.
    static func signal(_ server: ServerConfig) async {
        guard let mgr = NSFileProviderManager(for: domain(for: server)) else { return }
        try? await mgr.signalEnumerator(for: .rootContainer)
        try? await mgr.signalEnumerator(for: .workingSet)
    }
    /// URL that opens the Files app. Deep-linking straight into a provider folder is not
    /// reliable across iOS versions, so this opens Files' Browse view; the server is listed
    /// under Locations › Unraid Drive.
    static func filesAppURL(_ server: ServerConfig) async -> URL? {
        #if os(macOS)
        // On the Mac the location is a folder in the Finder sidebar: open it directly.
        guard let mgr = NSFileProviderManager(for: domain(for: server)) else { return nil }
        return try? await mgr.getUserVisibleURL(for: .rootContainer)
        #else
        URL(string: "shareddocuments://")
        #endif
    }
}

extension ServersModel {
    /// Debug builds only: `-seedServer <url> <apiKey>` adds a Direct server and `-seedDemo` the demo server without touching the UI; `-rebuildDomains` re-registers every location
    /// (used by simulator tests against a local gateway).
    func seedFromLaunchArguments() async {
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-seedDemo"), !hasDemo { await addDemo() }
        // `-selectShares <serverID>:<share,share>` (or `<serverID>:all`) stores a share selection (tests).
        if let i = args.firstIndex(of: "-selectShares"), args.count > i + 1, let s = servers.first(where: { $0.id == args[i + 1].split(separator: ":")[0] }) {
            let spec = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
            await setSelectedShares(s, spec.count > 1 && spec[1] != "all" ? spec[1].split(separator: ",").map(String.init) : nil)
        }
        if args.contains("-rebuildDomains") { for s in servers { try? await FileProviderDomains.rebuild(s) } }
        if args.contains("-testIntent") {
            do {
                let intent = SaveClipboardIntent(); intent.server = ServerStore().all().first { $0.isDemo }.map(ServerEntity.init)
                intent.folder = "documents"; intent.fileName = "Intent test {date}"
                let r = try await intent.perform(); NSLog("intent result: %@", String(describing: r.value ?? ""))
                let l = ListFolderIntent(); l.server = intent.server; l.folder = "documents"
                NSLog("list: %@", String(describing: try await l.perform().value ?? []))
            } catch { NSLog("intent failed: %@", error.localizedDescription) }
        }
        #if os(macOS)
        if args.contains("-evictAll") {   // test hook for the "Free up space" path
            for s in servers { let n = await MaterializedItems.evictAll(for: FileProviderDomains.domain(for: s)); NSLog("evicted %d items for %@", n, s.name) }
        }
        #endif
        if let i = args.firstIndex(of: "-seedServer"), args.count > i + 2, let url = URL(string: args[i + 1]), !servers.contains(where: { $0.url == url }) {
            _ = try? await add(name: "Local test", url: url, apiKey: args[i + 2], cloudflare: nil)
        }
        // `-seedSync <localFolder> <remotePath> [mode]`: creates (once) a folder pair on the first non-demo
        // server and runs it — the automated regression of the sync engine against a local gateway.
        // `-listLocation [subpath]`: lists the Files/Finder location like the Files app does (the system
        // enumerates through the extension) — regression of the File Provider where Files is absent (simulator).
        if let i = args.firstIndex(of: "-listLocation"), let s = servers.first(where: { !$0.isDemo }) {
            let sub = args.count > i + 1 && !args[i + 1].hasPrefix("-") ? args[i + 1] : ""
            try? await Task.sleep(for: .seconds(3))
            if let mgr = NSFileProviderManager(for: FileProviderDomains.domain(for: s)) {
                do {
                    try? await mgr.signalEnumerator(for: .workingSet)
                    try? await mgr.signalEnumerator(for: .rootContainer)
                    let root = try await mgr.getUserVisibleURL(for: .rootContainer)
                    for dir in sub.isEmpty ? [""] : ["", sub] {
                        let url = dir.isEmpty ? root : root.appendingPathComponent(dir)
                        var names: [String] = []
                        for attempt in 1...10 {
                            names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                            if !names.isEmpty { break }
                            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { _ in }
                            try? await Task.sleep(for: .seconds(2)); _ = attempt
                        }
                        Diag.info("listLocation", "\(dir.isEmpty ? "/" : dir): \(names.count) entries: \(names.sorted().prefix(12).joined(separator: ", "))")
                    }
                } catch { Diag.error("listLocation", "user-visible URL", error) }
            }
        }
        // `-removeSync <remotePath>`: drops the pair created by -seedSync (app and gateway) — test cleanup.
        if let i = args.firstIndex(of: "-removeSync"), args.count > i + 1 {
            for p in SyncStore.all() where p.remotePath == args[i + 1] { await SyncCoordinator.shared.remove(p); Diag.info("sync", "-removeSync: removed \(p.id)") }
        }
        if let i = args.firstIndex(of: "-seedSync"), args.count > i + 2, let s = servers.first(where: { !$0.isDemo }) {
            var local = URL(fileURLWithPath: args[i + 1]), remote = args[i + 2]
            // `@container`: a sample folder inside the app's sandbox (the shell cannot write there, the sandboxed app can).
            if args[i + 1] == "@container", let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                local = base.appendingPathComponent("synctest", isDirectory: true)
                try? FileManager.default.createDirectory(at: local.appendingPathComponent("sub"), withIntermediateDirectories: true)
                try? "from the \(SyncCoordinator.deviceTag) \(Date())".write(to: local.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
                try? "deep".write(to: local.appendingPathComponent("sub/deep.txt"), atomically: true, encoding: .utf8)
            }
            let bm = try? SyncPair.bookmark(for: local)
            if bm == nil { Diag.error("sync", "-seedSync: cannot bookmark \(local.path) (sandbox?)") }
            if !SyncStore.pairs(for: s.id).contains(where: { $0.remotePath == remote }), let bm {
                var p = SyncPair(serverID: s.id, kind: .folder, localLabel: local.path, localBookmark: bm, remotePath: remote, mode: SyncMode(rawValue: args.count > i + 3 ? args[i + 3] : "both") ?? .both)
                p.schedule = .manual
                await SyncCoordinator.shared.save(p)
            }
            if let p = SyncStore.pairs(for: s.id).first(where: { $0.remotePath == remote }) { await SyncCoordinator.shared.run(p, trigger: "manual") }
        }
        #endif
    }
}
