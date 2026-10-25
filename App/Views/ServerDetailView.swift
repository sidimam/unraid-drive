import SwiftUI
import UnraidGatewayKit

struct ServerDetailView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @State private var dashboard: Dashboard?
    @State private var error: String?
    @State private var loading = false
    @State private var filesURL: URL?
    @State private var testing = false
    @State private var editing = false
    @State private var checking = false
    @State private var openSyncDebug = false
    @State private var confirmRebuild = false

    var body: some View {
        List {
            Section {
                healthRow
                if model.current?.id != server.id {
                    Button { model.select(server); NotificationCenter.default.post(name: AppNavigation.showFolders, object: nil) } label: { Label("Open its folders", systemImage: "folder.badge.gearshape") }
                }
                if let filesURL {
                    #if os(macOS)
                    Button { Task { await FileProviderDomains.revealInFinder(server) } } label: { Label("Open in Finder", systemImage: "folder") }
                    #else
                    Link(destination: filesURL) { Label("Open the Files app", systemImage: "folder") }
                    #endif
                }
                NavigationLink { SharesPickerView(server: server) } label: {
                    LabeledContent { Text(model.current(server).selectedShares == nil ? String(localized: "All shares") : String(localized: "\(model.current(server).selectedShares?.count ?? 0) shares")) } label: {
                        Label("Shares to show", systemImage: "externaldrive.badge.checkmark")
                    }
                }
                Button { testing = true } label: { Label("Test connection", systemImage: "stethoscope") }
                if !server.isDemo {
                    NavigationLink { SyncSettingsView(server: server) } label: {
                        LabeledContent { Text(syncSummary) } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    }
                }
                #if DEBUG
                // `-openSync`: straight into the Sync screen (regression screenshots).
                NavigationLink(isActive: $openSyncDebug) { SyncSettingsView(server: server) } label: { EmptyView() }.hidden()
                #endif
                if !server.isDemo {
                    Button { editing = true } label: { Label("Edit server or credentials", systemImage: "pencil") }
                    // 1.5.2: the Files/Finder location rebuilt on demand (fresh database and item cache) —
                    // the remedy when Files shows "Content unavailable" for this server.
                    Button { confirmRebuild = true } label: {
                        Label(checking ? String(localized: "Rebuilding…") : String(localized: "Rebuild the Files location"), systemImage: "arrow.clockwise.icloud")
                    }
                    .disabled(checking)
                    .confirmationDialog("Rebuild the Files location?", isPresented: $confirmRebuild, titleVisibility: .visible) {
                        Button("Rebuild") { Task { checking = true; await model.maintainLocationsIfNeeded(force: true, only: server); await model.refreshHealth(server); checking = false } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The location is removed and registered again: files already downloaded on this device are downloaded again when you open them, changes not yet uploaded are lost. Use it when Files shows \"Content unavailable\" for this server.")
                    }
                }
            }
            #if os(macOS)
            LocationStateBanner(server: server)
            #endif
            if server.isDemo {
                Section { Label("Demo server: sample data stored on this device only.", systemImage: "info.circle") }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Run connection test") { testing = true }
                }
            }
            if let d = dashboard {
                systemSection(d)
                arraySection(d)
                sharesSection(d)
                dockerSection(d)
            } else if loading {
                Section { HStack { ProgressView(); Text("Loading dashboard…") } }
            }
        }
        .navigationTitle(Text(verbatim: server.name))
        .sheet(isPresented: $testing) { ConnectionTestView(server: server) }
        .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { AddServerView(editing: model.servers.first { $0.id == server.id } ?? server) }
        .refreshable { await load() }
        .task { await load(); filesURL = await FileProviderDomains.filesAppURL(server); await model.refreshHealth(server) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openSync") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openSyncDebug = true } }
            #endif
        }
    }

    /// Build 42/44: the server's health at a glance — only what concerns Unraid Drive and the
    /// gateway — with every warning or error listed and, when there is one, the action that fixes it.
    @ViewBuilder private var healthRow: some View {
        let h = model.health[server.id]
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HealthDot(health: h).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(HealthDot.title(h)).font(.body)
                if let h, h.level == .ok {
                    Text("Gateway, credentials, Files/Finder location and transfers look fine.").font(.footnote).foregroundStyle(.secondary)
                } else if h == nil {
                    Text("Checking the gateway…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        if let h, !h.issues.isEmpty {
            ForEach(h.issues) { issue in issueRow(issue) }
        }
    }

    private func issueRow(_ issue: ServerHealth.Issue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.level == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.level == .error ? .red : .orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceTitle(issue.source)).font(.footnote).foregroundStyle(.secondary)
                Text(issue.detail).font(.callout)
                switch issue.action {
                case .openSystemSettings:
                    #if os(macOS)
                    Button("Open System Settings") { LocationErrorText.openExtensionsSettings() }.font(.callout)
                    #else
                    Button(checking ? "Checking…" : "Check now") { Task { checking = true; await model.maintainLocationsIfNeeded(force: true, only: server); await model.refreshHealth(server); checking = false } }.disabled(checking).font(.callout)
                    #endif
                case .checkLocation:
                    Button(checking ? "Checking…" : "Check now") { Task { checking = true; await model.maintainLocationsIfNeeded(force: true, only: server); await model.refreshHealth(server); checking = false } }.disabled(checking).font(.callout)
                case .signIn:
                    Button("Edit server or credentials") { editing = true }.font(.callout)
                case .openDiagnostics:
                    NavigationLink { DiagnosticsView() } label: { Text("Open Diagnostics and log") }.font(.callout)
                case .openSync:
                    NavigationLink { SyncSettingsView(server: server) } label: { Text("Open Sync") }.font(.callout)
                case .reRegister:
                    Button("Connect again") { Task { await model.registerRestoredDevices(timeout: 20); await model.refreshHealth(server) } }.font(.callout)
                case .retryTransfers:
                    Button("Refresh the Files location") { Task { await FileProviderDomains.signal(server); await model.refreshHealth(server) } }.font(.callout)
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func sourceTitle(_ s: ServerHealth.Source) -> LocalizedStringKey {
        switch s {
        case .gateway: return "Gateway"
        case .credentials: return "Credentials"
        case .location: return "Files / Finder location"
        case .transfers: return "Transfers"
        case .device: return "Device registration"
        case .shares: return "Shares"
        case .sync: return "Sync"
        }
    }

    private var syncSummary: String {
        let pairs = SyncStore.pairs(for: server.id)
        if pairs.isEmpty { return String(localized: "Off") }
        let active = pairs.filter(\.isActive).count
        return String(localized: "\(active) of \(pairs.count) active")
    }

    private func cpuLine(_ cpu: Dashboard.Info.CPU) -> String {
        let brand = cpu.brand ?? ""
        let cores = cpu.cores ?? 0
        let threads = cpu.threads ?? 0
        return "\(brand) · \(cores)C/\(threads)T"
    }

    @ViewBuilder private func systemSection(_ d: Dashboard) -> some View {
        Section(header: SectionTitle("System")) {
            LabeledContent("Hostname", value: d.info?.os?.hostname ?? "—")
            LabeledContent("Unraid", value: d.info?.os?.release ?? "—")
            if let cpu = d.info?.cpu { LabeledContent("CPU", value: cpuLine(cpu)) }
            if let p = d.metrics?.cpu?.percentTotal { gauge("CPU load", p) }
            if let p = d.metrics?.memory?.percentTotal { gauge("Memory", p) }
            NavigationLink { SystemInfoView(server: server) } label: { Label("System information", systemImage: "info.circle") }
        }
    }

    @ViewBuilder private func arraySection(_ d: Dashboard) -> some View {
        Section(header: SectionTitle("Array")) {
            LabeledContent("State") {
                Text(d.array?.state ?? "—").foregroundStyle(d.array?.state == "STARTED" ? .green : .orange)
            }
            if let c = d.arrayBytes {
                let pct = Double(c.used) / Double(max(c.total, 1)) * 100
                gauge("Used \(bytes(c.used)) of \(bytes(c.total))", pct)
            }
            if let p = d.array?.parityCheckStatus, p.running == true {
                LabeledContent("Parity check", value: String(p.progress ?? 0) + "%")
            }
            ForEach(d.array?.disks ?? [], id: \.name) { disk in
                diskRow(disk)
            }
        }
    }

    @ViewBuilder private func sharesSection(_ d: Dashboard) -> some View {
        Section(header: SectionTitle("Shares")) {
            ForEach((d.shares ?? []).filter { $0.used != nil }, id: \.name) { s in
                shareRow(s)
            }
        }
    }

    /// Only the container that serves this app is relevant here; the rest of the Docker
    /// list belongs to Unraid's own UI.
    static func isGateway(_ c: Dashboard.Container) -> Bool {
        let haystack = ([c.image ?? ""] + c.names).joined(separator: " ").lowercased()
        return haystack.contains("unraid-gateway")
    }

    @ViewBuilder private func dockerSection(_ d: Dashboard) -> some View {
        let gateway = (d.docker?.containers ?? []).filter { Self.isGateway($0) }
        Section {
            if gateway.isEmpty {
                Label("No unraid-gateway container found in Docker.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
            } else {
                ForEach(gateway) { c in containerRow(c) }
            }
        } header: {
            Text("Gateway container")
        } footer: {
            Text("The container this app talks to. Other containers are managed from the Unraid web UI.")
        }
    }

    private func diskRow(_ disk: Dashboard.Array.Disk) -> some View {
        let temp: String = disk.temp.map { String($0) + "°C" } ?? ""
        let status: String = disk.status ?? ""
        let ok: Bool = status == "DISK_OK"
        return LabeledContent(disk.name) {
            HStack {
                Text(temp)
                Text(status).foregroundStyle(ok ? Color.secondary : Color.orange)
            }.font(.callout)
        }
    }

    private func containerRow(_ c: Dashboard.Container) -> some View {
        let color: Color = c.state == "RUNNING" ? .green : (c.state == "PAUSED" ? .orange : .gray)
        let webURL: URL? = c.webUiUrl.flatMap { URL(string: $0) }
        return HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.displayName)
                Text(c.image ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if c.isUpdateAvailable == true { Image(systemName: "arrow.down.circle").foregroundStyle(.blue) }
            if let webURL { Link(destination: webURL) { Image(systemName: "safari") } }
        }
    }

    private func shareRow(_ s: Dashboard.Share) -> some View {
        let used = bytes((s.used ?? 0) * 1024)
        return VStack(alignment: .leading, spacing: 2) {
            HStack { Text(s.name); Spacer(); Text(used + " used").foregroundStyle(.secondary).font(.callout) }
            if let c = s.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func gauge(_ title: String, _ percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(percent.rounded()))%").foregroundStyle(.secondary) }.font(.callout)
            ProgressView(value: min(max(percent, 0), 100), total: 100).tint(percent > 90 ? .red : (percent > 75 ? .orange : AppIconColor.currentTint))
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .binary)
    }

    private func load() async {
        guard let client = model.client(for: server) else { error = "API key missing from Keychain"; return }
        loading = true; defer { loading = false }
        do {
            dashboard = try await client.graphQL(Dashboard.query, as: Dashboard.self)
            error = nil
            if let root = try? await client.list("/") { await model.adoptServerIDsIfNeeded(server, entries: root.entries) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
