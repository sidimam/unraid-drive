import SwiftUI
#if os(macOS)
import ServiceManagement
#endif
import UnraidGatewayKit

/// App settings, laid out like aMule Remote: one "App settings" group (theme, language, icon colour),
/// iCloud sync, and an "App info" group with version, author, license and links.
struct SettingsView: View {
    /// Present the "Add a profile" form as soon as the sheet appears (quick action, menu bar panel).
    var addProfileOnAppear = false
    @State private var adding = false
    #if os(macOS)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(DockPolicy.key, store: AppGroup.defaults) private var menuBarOnly = false
    @AppStorage(LaunchPolicy.key, store: AppGroup.defaults) private var startMinimized = false
    #endif
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var pairTV = false
    @State private var confirmRemoveCloud = false
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key, store: AppGroup.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(AppIconColor.storageKey, store: AppGroup.defaults) private var iconColor = "default"

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (build \(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Build 42: the profiles (servers, connections, credentials) live here, nowhere else.
                Section {
                    ForEach(model.servers) { s in
                        NavigationLink { ServerDetailView(server: s) } label: { ProfileRow(server: s, isCurrent: model.current?.id == s.id, health: model.health[s.id]) }
                    }
                    .onDelete { idx in
                        let victims = idx.map { model.servers[$0] }
                        Task { for v in victims { await model.remove(v) } }
                    }
                    if cloud.shouldOfferRestore(localServers: model.servers) {
                        Button { Task { busy = true; await model.restoreFromCloudAndRegister(); busy = false } } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "icloud.and.arrow.down") }.disabled(busy)
                    }
                    Button { adding = true } label: { Label("Add a profile", systemImage: "plus.circle") }
                    if !model.hasDemo { Button { Task { await model.addDemo() } } label: { Label("Try the demo", systemImage: "sparkles") } }
                } header: { SectionTitle("Profiles") } footer: {
                    #if os(macOS)
                    Text("A profile is an Unraid server reached through its unraid-gateway, with its own connection mode and credentials. The app opens on the current profile; every profile is also a location in the Finder sidebar. Open a profile for its dashboard, shares to show, connection test and credentials; right-click to remove it.")
                    #else
                    Text("A profile is an Unraid server reached through its unraid-gateway, with its own connection mode and credentials. The app opens on the current profile; every profile is also a location in the Files app. Open a profile for its dashboard, shares to show, connection test and credentials; swipe left to remove it.")
                    #endif
                }
                Section {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases) { a in Label(a.label, systemImage: a.icon).tag(a.rawValue) }
                    } label: { Label("Theme", systemImage: "circle.lefthalf.filled") }
                    Picker(selection: $language) {
                        ForEach(AppLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                    } label: { Label("Language", systemImage: "globe") }
                    .onChange(of: language) { _, v in (AppLanguage(rawValue: v) ?? .system).applySystemOverride() }
                    #if os(iOS) || os(macOS)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("App colour", systemImage: "paintpalette")
                        IconColorPicker(selection: $iconColor)
                    }
                    .onChange(of: iconColor) { _, v in AppIconColor.apply(v) }
                    #endif
                    Button { AppNotifications.openSystemSettings() } label: {
                        HStack { Label("Notifications", systemImage: "bell.badge"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    }
                    if model.servers.contains(where: { !$0.isDemo }) {
                        Button { pairTV = true } label: { Label("Pair an Apple TV", systemImage: "appletv") }
                    }
                    #if os(macOS)
                    Toggle(isOn: Binding(get: { launchAtLogin }, set: { v in
                        LoginItem.set(v)
                        launchAtLogin = LoginItem.isEnabled })) { Label("Launch at login", systemImage: "power") }
                        .onAppear { launchAtLogin = LoginItem.isEnabled }
                    Toggle(isOn: $menuBarOnly) { Label("Show only in the menu bar", systemImage: "menubar.rectangle") }
                        .onChange(of: menuBarOnly) { _, _ in DockPolicy.apply() }
                    Toggle(isOn: $startMinimized) { Label("Start without a window", systemImage: "macwindow.badge.plus") }
                    #endif
                } header: { SectionTitle("App settings") } footer: {
                    #if os(macOS)
                    Text("System follows the Mac settings for theme and language. A forced language applies to this app only; a few system-provided texts follow at the next launch. The icon colour also colours the app's titles, headers and controls, and the Dock icon while the app runs. “Start without a window” opens the app in the menu bar only (or menu bar and Dock, when the Dock icon is kept): the window comes back from the menu bar panel or the Dock icon. Launching at login always starts this way.")
                    #else
                    Text("System follows the device settings for theme and language. A forced language applies to this app only; a few system-provided texts follow at the next launch. The icon colour also colours the app's titles, headers and controls; Apple Vision Pro keeps the layered icon.")
                    #endif
                }

                Section {
                    Toggle(isOn: Binding(get: { cloud.enabled }, set: { v in Task { busy = true; await cloud.setEnabled(v); busy = false } })) {
                        Label("Sync configuration with iCloud", systemImage: "icloud")
                    }.disabled(busy)
                    // Always visible (build 37): until build 36 these rows only appeared while the switch
                    // was on, which read as "the sync buttons disappeared".
                    LabeledContent { Text("\(cloud.remoteServerCount)") } label: { Label("Servers in iCloud", systemImage: "externaldrive.badge.icloud") }
                    #if DEVELOPER_ID
                    if cloud.documentMode == .syncedFolder {
                        LabeledContent { Text("synced folder") } label: { Label("Homebrew build", systemImage: "shippingbox") }
                    }
                    #endif
                    if let d = cloud.lastSync { LabeledContent { Text(d.formatted(date: .abbreviated, time: .shortened)) } label: { Label("Last sync", systemImage: "clock.arrow.2.circlepath") } }
                    Button { Task { busy = true; _ = await cloud.pull(); cloud.push(); busy = false } } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath.icloud") }
                        .disabled(busy || !cloud.enabled)
                    Button {
                        Task { busy = true; await model.restoreFromCloudAndRegister(); busy = false }
                    } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "arrow.down.circle") }
                        .disabled(busy || cloud.remoteServerCount == 0)
                    if cloud.remoteServerCount > 0 {
                        Button(role: .destructive) { confirmRemoveCloud = true } label: { Label("Remove the configuration from iCloud", systemImage: "icloud.slash") }
                            .confirmationDialog("Remove the server list from iCloud?", isPresented: $confirmRemoveCloud) {
                                Button("Remove from iCloud", role: .destructive) { cloud.removeCloudCopy() }
                            } message: { Text("The other devices keep their configuration; only the shared copy is deleted. Secrets in iCloud Keychain are not touched.") }
                    }
                    if let e = cloud.lastError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                } header: { SectionTitle("iCloud") } footer: {
                    Text("When on, the server list (names, URLs, connection mode, shares to show) is saved as a readable servers.json in iCloud Drive › Unraid Drive and in iCloud's key-value storage, and the API keys, Cloudflare tokens and Unraid passwords in iCloud Keychain (the Passwords of your Apple account), end-to-end encrypted — never in the file. After restoring or replacing a device, Restore brings the servers back and registers this device on each gateway. Turning sync off keeps the copies in iCloud for the other devices. The demo server is never synced.")
                    #if DEVELOPER_ID
                    Text("Apple grants an iCloud Drive folder only to App Store apps: this Homebrew build reads and writes the servers.json that iCloud Drive syncs from your other devices, and always keeps the list in iCloud key-value storage.")
                    #endif
                }

                Section {
                    NavigationLink { DiagnosticsView() } label: { Label("Diagnostics and log", systemImage: "waveform.path.ecg") }
                } header: { SectionTitle("Support") } footer: {
                    Text("Rotating log of app and extension, debug logging and a report to share when something does not work.")
                }
                Section {
                    LabeledContent { Text(versionString) } label: { Label("Unraid Drive", systemImage: "app.badge") }
                    LabeledContent { Text("Simone Di Mambro") } label: { Label("Author", systemImage: "person") }
                    NavigationLink { LicenseView() } label: { Label("License (MIT)", systemImage: "doc.text") }
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-drive")!) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-gateway")!) { Label("unraid-gateway (server side)", systemImage: "shippingbox") }
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-drive/wiki")!) { Label("Setup guide (wiki)", systemImage: "book") }
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-drive/issues")!) { Label("Report a problem", systemImage: "ladybug") }
                    Link(destination: URL(string: "https://sidimam.github.io/unraid-drive/")!) { Label("Privacy policy", systemImage: "hand.raised") }
                } header: { SectionTitle("App info") } footer: {
                    Text("Unraid Drive is an independent open-source project and is not affiliated with Lime Technology / Unraid. Unraid is a trademark of Lime Technology, Inc. The app talks only to your own gateway: no accounts, no analytics, no third-party servers.")
                }
            }
            .groupedFormStyle()
            .sheet(isPresented: $pairTV) { PairTVView() }
            .sheet(isPresented: $adding) { AddServerView().presentationDetents([.large]) }
            .onAppear { if addProfileOnAppear { adding = true } }
            .onReceive(NotificationCenter.default.publisher(for: AppNavigation.addProfile)) { _ in adding = true }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheetFrame()
    }
}

/// A profile in Settings: icon by connection mode, name, user · host, the health dot and a mark on the current one.
struct ProfileRow: View {
    let server: ServerConfig
    let isCurrent: Bool
    let health: ServerHealth?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.isDemo ? "sparkles" : (server.accessMode == .cloudflareAccess ? "cloud.fill" : "externaldrive.fill")).foregroundStyle(.tint).frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name).font(.headline)
                    if isCurrent { Text("current").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.tint.opacity(0.15), in: Capsule()).foregroundStyle(.tint) }
                }
                Text(server.isDemo ? String(localized: "Sample data, offline") : (server.username.map { "\($0) · " } ?? "") + (server.url.host ?? server.url.absoluteString)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HealthDot(health: health)
        }
    }
}

