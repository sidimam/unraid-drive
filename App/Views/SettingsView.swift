import SwiftUI
import UnraidGatewayKit

/// App settings, laid out like aMule Remote: one "App settings" group (theme, language, icon colour),
/// iCloud sync, and an "App info" group with version, author, license and links.
struct SettingsView: View {
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
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
                Section {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases) { a in Label(a.label, systemImage: a.icon).tag(a.rawValue) }
                    } label: { Label("Theme", systemImage: "circle.lefthalf.filled") }
                    Picker(selection: $language) {
                        ForEach(AppLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                    } label: { Label("Language", systemImage: "globe") }
                    .onChange(of: language) { _, v in (AppLanguage(rawValue: v) ?? .system).applySystemOverride() }
                    #if os(iOS)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Icon colour", systemImage: "paintpalette")
                        IconColorPicker(selection: $iconColor)
                    }
                    .onChange(of: iconColor) { _, v in AppIconColor.apply(v) }
                    #endif
                } header: { SectionTitle("App settings") } footer: {
                    Text("System follows the device settings for theme and language. A forced language applies to this app only; a few system-provided texts follow at the next launch. The icon colour applies to iPhone and iPad; Apple Vision Pro keeps the layered icon.")
                }

                Section {
                    Toggle(isOn: Binding(get: { cloud.enabled }, set: { v in Task { busy = true; await cloud.setEnabled(v); busy = false } })) {
                        Label("Sync configuration with iCloud", systemImage: "icloud")
                    }.disabled(busy)
                    if cloud.enabled {
                        LabeledContent { Text("\(cloud.remoteServerCount)") } label: { Label("Servers in iCloud", systemImage: "externaldrive.badge.icloud") }
                        if let d = cloud.lastSync { LabeledContent { Text(d.formatted(date: .abbreviated, time: .shortened)) } label: { Label("Last sync", systemImage: "clock.arrow.2.circlepath") } }
                        Button { Task { busy = true; _ = await cloud.pull(); cloud.push(); busy = false } } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath.icloud") }.disabled(busy)
                    }
                    if let e = cloud.lastError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                } header: { SectionTitle("iCloud") } footer: {
                    Text("When on, the server list (names, URLs, connection mode) is stored in your iCloud account and the API keys and Cloudflare tokens in iCloud Keychain, end-to-end encrypted. After restoring or replacing your iPhone, the app finds its configuration again. When off, everything stays on this device only. The demo server is never synced.")
                }
                if !cloud.enabled && cloud.remoteServerCount > 0 {
                    Section {
                        Button {
                            Task { busy = true; await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains(); busy = false }
                        } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "arrow.down.circle") }
                    } footer: {
                        Text("A configuration saved by this app is present in your iCloud account. Restoring turns sync on.")
                    }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
