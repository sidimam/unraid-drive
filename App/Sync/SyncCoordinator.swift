import Foundation
import Network
import UnraidGatewayKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Owns the sync pairs of this installation: keeps them in the app group, mirrors them on the
/// gateway (`/api/v1/syncs`), schedules the runs (change watching + periodic scans on the Mac,
/// hourly/daily timers, manual) and exposes progress to the UI. One pair runs at a time per server.
@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published private(set) var pairs: [SyncPair] = []
    @Published private(set) var progress: [String: SyncEngine.Progress] = [:]
    @Published private(set) var lastFiles: [String: [SyncFileRecord]] = [:]

    private var engines: [String: SyncEngine] = [:]
    private var photoRuns: [String: PhotosBackup] = [:]
    #if os(macOS)
    private var watchers: [String: FSEventsWatcher] = [:]
    #endif
    private var timers: [String: Timer] = [:]
    private let path = NWPathMonitor()
    private var expensive = false
    private let store = ServerStore()
    private let keychain = KeychainStore()
    static let periodicScan: TimeInterval = 15 * 60

    private init() {
        reload()
        path.pathUpdateHandler = { [weak self] p in Task { @MainActor in self?.expensive = p.isExpensive || p.isConstrained } }
        path.start(queue: DispatchQueue(label: "sync-path"))
        NotificationCenter.default.addObserver(forName: SyncStore.changedNotification, object: nil, queue: .main) { [weak self] _ in self?.reload() }
    }

    nonisolated static var deviceTag: String {
        #if os(macOS)
        return "Mac"
        #elseif os(visionOS)
        return "Vision Pro"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    func reload() {
        pairs = SyncStore.all()
        for p in pairs { lastFiles[p.id] = SyncStore.recentFiles(p.id) }
        schedule()
    }

    func pairs(for server: ServerConfig) -> [SyncPair] { pairs.filter { $0.serverID == server.id } }
    func isRunning(_ id: String) -> Bool { progress[id] != nil && progress[id]?.phase != "done" }

    private func client(forServer id: String) -> GatewayClient? {
        guard let s = store.all().first(where: { $0.id == id }) else { return nil }
        return GatewayClientFactory.client(for: s, keychain: keychain)
    }

    // MARK: pairs

    /// Saves a pair (new or edited), registers it on the gateway and schedules it.
    func save(_ pair: SyncPair) async {
        var p = pair
        SyncStore.save(p)
        if let c = client(forServer: p.serverID) {
            do {
                let remote = try await c.putSync(p)
                p.pausedByGateway = remote.enabled ? nil : (remote.disabledBy ?? "gateway")
                SyncStore.save(p)
            } catch { Diag.error("sync", "\(p.localLabel): registering on the gateway", error) }
        }
        reload()
    }

    func remove(_ pair: SyncPair) async {
        stopWatching(pair.id)
        SyncStore.remove(pair.id)
        if let c = client(forServer: pair.serverID) { try? await c.deleteSync(pair.id) }
        reload()
    }

    func setEnabled(_ pair: SyncPair, _ on: Bool) async {
        var p = pair; p.enabled = on
        SyncStore.save(p)
        if let c = client(forServer: p.serverID) {
            if let remote = try? await c.setSyncEnabled(p.id, on) { p.pausedByGateway = remote.enabled ? nil : (remote.disabledBy ?? "gateway"); SyncStore.save(p) }
        }
        reload()
    }

    /// Pulls the gateway's enabled flags (the web UI may have paused a pair) for one server.
    func refreshFromGateway(_ server: ServerConfig) async {
        guard let c = client(forServer: server.id), let remote = try? await c.remoteSyncs() else { return }
        let byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var changed = false
        for var p in pairs(for: server) {
            if let r = byID[p.id] {
                let paused = r.enabled ? nil : (r.disabledBy ?? "gateway")
                if paused != p.pausedByGateway { p.pausedByGateway = paused; SyncStore.save(p); changed = true }
            } else {
                // Unknown to the gateway (new gateway, registry wiped): register it again.
                try? await c.putSync(p)
            }
        }
        if changed { reload() }
    }

    // MARK: scheduling

    private func schedule() {
        for (id, t) in timers where !pairs.contains(where: { $0.id == id }) { t.invalidate(); timers[id] = nil }
        #if os(macOS)
        for id in watchers.keys where !pairs.contains(where: { $0.id == id }) { watchers[id] = nil }
        #endif
        for p in pairs {
            timers[p.id]?.invalidate(); timers[p.id] = nil
            guard p.isActive else { stopWatching(p.id); continue }
            switch p.schedule {
            case .manual: stopWatching(p.id)
            case .continuous:
                startWatching(p)
                timers[p.id] = Timer.scheduledTimer(withTimeInterval: Self.periodicScan, repeats: true) { [weak self] _ in Task { @MainActor in await self?.run(p, trigger: "scheduled") } }
            case .hourly:
                stopWatching(p.id)
                timers[p.id] = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in await self?.run(p, trigger: "scheduled") } }
            case .daily:
                stopWatching(p.id)
                timers[p.id] = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in Task { @MainActor in await self?.run(p, trigger: "scheduled") } }
            }
        }
    }

    private func startWatching(_ p: SyncPair) {
        #if os(macOS)
        guard p.kind == .folder, watchers[p.id] == nil, let url = p.resolveLocalURL() else { return }
        _ = url.startAccessingSecurityScopedResource()
        watchers[p.id] = FSEventsWatcher(url: url) { [weak self] in Task { @MainActor in await self?.run(p, trigger: "change") } }
        #endif
    }
    private func stopWatching(_ id: String) {
        #if os(macOS)
        watchers[id] = nil
        #endif
    }

    /// Runs what is due (app became active, background task): every active pair whose last run
    /// is older than its schedule, photos/downloads included.
    func runDue(trigger: String) async {
        for p in pairs where p.isActive {
            let age = Date().timeIntervalSince(p.lastRun?.at ?? .distantPast)
            let due: Bool
            switch p.schedule {
            case .manual: due = false
            case .continuous: due = age > Self.periodicScan
            case .hourly: due = age > 3600
            case .daily: due = age > 86_400
            }
            if due { await run(p, trigger: trigger) }
        }
    }

    // MARK: running

    func run(_ pair: SyncPair, trigger: String) async {
        guard !isRunning(pair.id) else { return }
        guard let fresh = SyncStore.pair(pair.id) else { return }
        guard fresh.isActive || trigger == "manual" else { return }
        if fresh.wifiOnly, expensive, trigger != "manual" {
            Diag.info("sync", "\(fresh.localLabel): skipped, not on Wi-Fi"); return
        }
        guard let c = client(forServer: fresh.serverID) else {
            finish(fresh, SyncRunSummary(status: .failed, error: String(localized: "Credentials missing from the Keychain: sign in again."), trigger: trigger), []); return
        }
        // Paused on the gateway since the last run? One cheap request before moving any file.
        if let remote = try? await c.remoteSyncs().first(where: { $0.id == fresh.id }), !remote.enabled {
            var p = fresh; p.pausedByGateway = remote.disabledBy ?? "gateway"; SyncStore.save(p); reload()
            Diag.info("sync", "\(fresh.localLabel): paused on the gateway, not run"); return
        }
        progress[fresh.id] = .init(phase: "scanning", done: 0, total: 0, current: nil, bytes: 0)
        let id = fresh.id
        let onProgress: @Sendable (SyncEngine.Progress) -> Void = { p in Task { @MainActor in SyncCoordinator.shared.progress[id] = p } }
        let result: (SyncRunSummary, [SyncFileRecord])
        switch fresh.kind {
        case .photos:
            guard await PhotosBackup.authorize() else {
                finish(fresh, SyncRunSummary(status: .failed, error: String(localized: "Photos access is not allowed: enable it in Settings › Privacy › Photos."), trigger: trigger), []); progress[id] = nil; return
            }
            let b = PhotosBackup(client: c, pair: fresh, onProgress: onProgress)
            photoRuns[id] = b
            result = await b.run(trigger: trigger)
            photoRuns[id] = nil
        case .folder, .downloads:
            let e = SyncEngine(client: c, pair: fresh, deviceTag: Self.deviceTag, onProgress: onProgress)
            engines[id] = e
            result = await e.run(trigger: trigger)
            engines[id] = nil
        }
        progress[id] = nil
        await report(fresh, result.0, result.1, client: c)
    }

    func cancel(_ pair: SyncPair) async {
        await engines[pair.id]?.cancel()
        await photoRuns[pair.id]?.cancel()
    }

    private func report(_ pair: SyncPair, _ run: SyncRunSummary, _ files: [SyncFileRecord], client: GatewayClient) async {
        var p = pair
        do {
            let remote = try await client.reportSyncRun(p.id, run, files: files)
            p.pausedByGateway = remote.enabled ? nil : (remote.disabledBy ?? "gateway")
        } catch GatewayError.conflict(let why) where why.contains("paused") || why.contains("sync_disabled") {
            p.pausedByGateway = "gateway"
            Diag.info("sync", "\(p.localLabel): paused on the gateway")
        } catch {
            Diag.error("sync", "\(p.localLabel): reporting the run", error)
        }
        finish(p, run, files)
    }

    private func finish(_ pair: SyncPair, _ run: SyncRunSummary, _ files: [SyncFileRecord]) {
        var p = pair; p.lastRun = run
        SyncStore.save(p)
        SyncStore.appendFiles(p.id, files)
        if run.status == .failed || run.status == .partial {
            AppNotifications.post(id: "sync." + p.id, title: String(localized: "Sync \(p.localLabel): \(run.status == .failed ? String(localized: "failed") : String(localized: "with problems"))"),
                                  body: run.error ?? String(localized: "\(run.errors) errors, \(run.conflicts) conflicts"), thread: "sync")
        }
        reload()
    }
}
