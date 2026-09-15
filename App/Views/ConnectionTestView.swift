import SwiftUI
import FileProvider
import UnraidGatewayKit

/// Step-by-step connectivity check for a configured server.
struct ConnectionTestView: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig

    struct Step: Identifiable {
        enum State { case pending, running, ok(String), failed(String) }
        let id: String
        let title: LocalizedStringKey
        var state: State = .pending
    }

    @State private var steps: [Step] = [
        Step(id: "reach", title: "Gateway reachable"),
        Step(id: "auth", title: "API key accepted"),
        Step(id: "shares", title: "Shares listed"),
        Step(id: "write", title: "Write access"),
        Step(id: "files", title: Self.locationTitle),
    ]
    static var locationTitle: LocalizedStringKey {
        #if os(macOS)
        "Finder location registered"
        #else
        "Files app location registered"
        #endif
    }
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Server", value: server.name)
                    LabeledContent("URL", value: server.url.absoluteString).font(.callout)
                    LabeledContent("Connection", value: label(server.accessMode))
                }
                Section(header: SectionTitle("Checks")) {
                    ForEach(steps) { s in
                        HStack(alignment: .top, spacing: 12) {
                            icon(s.state).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                if let d = detail(s.state) { Text(d).font(.caption).foregroundStyle(isFailed(s.state) ? .red : .secondary) }
                            }
                        }
                    }
                }
                if let hint = hint {
                    Section(header: SectionTitle("What to do")) {
                        Text(hint).font(.callout)
                        #if os(macOS)
                        if locationNeedsSwitch { Button { LocationErrorText.openExtensionsSettings() } label: { Label("Open System Settings", systemImage: "gearshape") } }
                        #endif
                    }
                }
                Section {
                    Button { copyReport() } label: { Label(copied ? "Report copied" : "Copy report for support", systemImage: copied ? "checkmark" : "doc.on.clipboard") }
                        .disabled(running)
                    NavigationLink { DiagnosticsView() } label: { Label("Diagnostics and log", systemImage: "waveform.path.ecg") }
                } footer: { Text("The report contains the results above, the app and device details and the last lines of the log. It never includes API keys or tokens.") }
            }
            .navigationTitle("Test connection")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(running ? "Testing…" : "Run again") { Task { await run() } }.disabled(running)
                }
            }
            .task { await run() }
        }
        .sheetFrame()
    }

    @State private var copied = false
    @State private var locationNeedsSwitch = false

    private func copyReport() {
        var lines = [String]()
        for s in steps {
            let mark: String
            switch s.state { case .ok: mark = "OK  "; case .failed: mark = "FAIL"; case .running: mark = "…   "; case .pending: mark = "-   " }
            lines.append("\(mark) \(s.id): \(detail(s.state) ?? "")")
        }
        let report = DiagnosticsReport.text(model: model, server: server, extra: ["Connection test:"] + lines)
        Clipboard.copy(report)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func label(_ m: AccessMode) -> String {
        switch m {
        case .direct: return String(localized: "Direct")
        case .cloudflareAccess: return String(localized: "Cloudflare Access")
        case .demo: return String(localized: "Demo")
        }
    }
    /// The outcome icons replace each other with the system symbol transition and bounce once when a
    /// step ends, like a native checklist; no custom drawing.
    private func icon(_ s: Step.State) -> some View {
        Group {
            switch s {
            case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
            case .running: ProgressView()
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).symbolEffect(.bounce, options: .nonRepeating)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).symbolEffect(.bounce, options: .nonRepeating)
            }
        }
        .contentTransition(.symbolEffect(.replace))
        .animation(.default, value: stateKey(s))
    }
    private func stateKey(_ s: Step.State) -> Int {
        switch s { case .pending: 0; case .running: 1; case .ok: 2; case .failed: 3 }
    }
    private func detail(_ s: Step.State) -> String? {
        switch s { case .ok(let d), .failed(let d): return d; default: return nil }
    }
    private func isFailed(_ s: Step.State) -> Bool { if case .failed = s { return true }; return false }

    private var hint: LocalizedStringKey? {
        guard let first = steps.first(where: { isFailed($0.state) }) else { return nil }
        switch first.id {
        case "reach": return "Open the URL in Safari on this device. Check the container is running, the Cloudflare Tunnel or reverse proxy is up, and that you are not using a LAN address from outside your network."
        case "auth": return "The gateway is up but rejected the key or the request never reached it. Use Edit to paste the API key again; with Cloudflare Access, check the two service token values and that the policy action is Service Auth."
        case "shares": return "Authenticated, but no shares are mounted in the container. Add Path mappings under /data/<name> in the container settings."
        case "write": return "Shares are read-only or the gateway runs with READ_ONLY=true. Check the volume access mode in the container settings."
        case "files":
            if locationNeedsSwitch {
                #if os(macOS)
                return "The Finder extension of Unraid Drive is switched off (this happens after some updates). Turn it on in System Settings › General › Login Items & Extensions › File Providers, then run the test again: the location comes back by itself, nothing to remove or re-add."
                #else
                return "The Files extension of Unraid Drive is switched off. In the Files app open Browse, tap ⋯ › Edit and turn on Unraid Drive, then run the test again."
                #endif
            }
            #if os(macOS)
            return "The Finder location is missing. Run the test again (it registers the location); if it keeps failing, quit and reopen Unraid Drive, then restart the Mac."
            #else
            return "The Files app location is missing. Run the test again (it registers the location); if it keeps failing, restart the device."
            #endif
        default: return nil
        }
    }

    private func set(_ id: String, _ state: Step.State) {
        if let i = steps.firstIndex(where: { $0.id == id }) { steps[i].state = state }
        switch state {
        case .ok(let d): Diag.info("test", "\(server.name) \(id): ok — \(d)")
        case .failed(let d): Diag.error("test", "\(server.name) \(id): FAILED — \(d)")
        default: break
        }
    }

    private func run() async {
        running = true; defer { running = false }
        locationNeedsSwitch = false
        Diag.info("test", "connection test for \(server.name) (\(server.accessMode), \(server.url.host ?? "?"))")
        for i in steps.indices { steps[i].state = .pending }
        guard let client = model.client(for: server) else {
            set("reach", .failed(String(localized: "Credentials missing from the Keychain. Use Edit to enter them again."))); return
        }
        // 1. reachability
        set("reach", .running)
        let t0 = Date()
        do {
            let h = try await client.health()
            set("reach", .ok(String(localized: "version \(h.version ?? "?") · \(Int(Date().timeIntervalSince(t0) * 1000)) ms")))
        } catch {
            set("reach", .failed(error.localizedDescription)); return
        }
        // 2. auth
        set("auth", .running)
        let login: LoginResponse
        do {
            login = try await client.login()
            let roles = (login.identity.roles ?? []).joined(separator: ", ")
            let who = login.user.map { String(localized: "user \($0) · ") } ?? ""
            set("auth", .ok(String(localized: "\(who)key \(login.identity.name ?? "?") · \(roles)") + (login.readOnly ? String(localized: " · gateway read-only") : "")))
        } catch {
            set("auth", .failed(error.localizedDescription)); return
        }
        // 3. shares
        set("shares", .running)
        let shares: [FSEntry]
        do {
            shares = try await client.list("/").entries
            await model.adoptServerIDsIfNeeded(server, entries: shares)
            if shares.isEmpty { set("shares", .failed(login.user == nil ? String(localized: "No shares mounted in the container") : String(localized: "Your Unraid user has no access to any mounted share"))) ; return }
            let perms = login.shares ?? [:]
            let cfg = model.current(server)
            let labels = shares.map { share -> String in
                var label = share.name
                if let p = perms[share.name] { label += " (\(p))" }
                if !cfg.showsShare(share.name) { label += " · " + String(localized: "hidden") }
                return label
            }
            set("shares", .ok(labels.joined(separator: ", ")))
        } catch {
            set("shares", .failed(error.localizedDescription)); return
        }
        // 4. write probe: create and delete a tiny folder in the first writable share
        set("write", .running)
        if login.readOnly {
            set("write", .failed(String(localized: "Gateway is configured READ_ONLY")))
        } else {
            var writable: String?
            var lastError = String(localized: "no writable share found")
            for share in shares where share.isDirectory && (login.shares?[share.name] ?? "rw") == "rw" {
                let probe = GatewayPath.join(share.path, ".unraid-drive-probe-\(UUID().uuidString.prefix(8))")
                do {
                    _ = try await client.mkdir(probe)
                    try await client.delete(probe, recursive: true)
                    writable = share.name; break
                } catch { lastError = error.localizedDescription }
            }
            if let w = writable { set("write", .ok(String(localized: "created and removed a test folder in \(w)"))) } else { set("write", .failed(lastError)) }
        }
        // 5. File Provider domain
        set("files", .running)
        do {
            let domains = try await NSFileProviderManager.domains()
            if domains.contains(where: { $0.identifier.rawValue == server.id }) {
                // Also wake the domain up: after a network error iOS keeps it paused until asked.
                await FileProviderDomains.signal(server)
                #if os(macOS)
                set("files", .ok(String(localized: "Finder › Unraid Drive – \(server.name) · refresh requested")))
                #else
                set("files", .ok(String(localized: "Files › Unraid Drive › \(server.name) · refresh requested")))
                #endif
            } else {
                try await FileProviderDomains.add(server)
                set("files", .ok(String(localized: "registered now")))
            }
        } catch {
            locationNeedsSwitch = LocationErrorText.needsUserAction(error)
            set("files", .failed(LocationErrorText.describe(error)))
        }
    }
}
