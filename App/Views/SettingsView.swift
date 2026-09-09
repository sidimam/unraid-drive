import SwiftUI
import UnraidGatewayKit

struct SettingsView: View {
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @AppStorage(Appearance.key, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key, store: AppGroup.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(AppIconColor.storageKey, store: AppGroup.defaults) private var iconColor = "default"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { a in Text(a.label).tag(a.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                    }
                    .onChange(of: language) { _, v in (AppLanguage(rawValue: v) ?? .system).applySystemOverride() }
                    #if os(iOS)
                    LabeledContent("App icon") { IconColorPicker(selection: $iconColor) }
                        .onChange(of: iconColor) { _, v in AppIconColor.apply(v) }
                    #endif
                } header: { SectionTitle("Appearance") } footer: {
                    Text("System follows the device settings. A forced language applies to this app only; a few system-provided texts follow at the next launch.")
                }
                Section {
                    Toggle(isOn: Binding(get: { cloud.enabled }, set: { v in Task { busy = true; await cloud.setEnabled(v); busy = false } })) {
                        Label("Sync configuration with iCloud", systemImage: "icloud")
                    }.disabled(busy)
                    if cloud.enabled {
                        LabeledContent("Servers in iCloud", value: "\(cloud.remoteServerCount)")
                        if let d = cloud.lastSync { LabeledContent("Last sync", value: d.formatted(date: .abbreviated, time: .shortened)) }
                        Button("Sync now") { Task { busy = true; _ = await cloud.pull(); cloud.push(); busy = false } }.disabled(busy)
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
                Section(header: SectionTitle("About")) {
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-drive/wiki")!) { Label("Setup guide (wiki)", systemImage: "book") }
                    Link(destination: URL(string: "https://github.com/sidimam/unraid-drive/issues")!) { Label("Report a problem", systemImage: "ladybug") }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
