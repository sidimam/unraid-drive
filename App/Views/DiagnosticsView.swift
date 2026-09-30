import SwiftUI
import FileProvider
import UnraidGatewayKit
#if os(macOS)
import AppKit
#endif

/// Settings › Diagnostics: the shared rotating log of app and extension, the *Debug logging*
/// switch, and export/copy of a support report that never contains secrets.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: ServersModel
    @State private var debug = Diag.debugEnabled
    @State private var lines: [String] = []
    @State private var size = 0
    @State private var exportURL: URL?
    @State private var copied = false
    @State private var confirmClear = false
    @State private var showErrorsOnly = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $debug) { Label("Debug logging", systemImage: "ladybug") }
                    .onChange(of: debug) { _, v in Diag.debugEnabled = v; refresh() }
                LabeledContent { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) } label: { Label("Log size", systemImage: "internaldrive") }
            } header: { SectionTitle("Logging") } footer: {
                Text("Errors, warnings and the main events are always recorded, by the app and by the Files/Finder extension, in files that rotate at \(Diag.maxFiles) × \(Diag.maxFileSize / 1_000_000) MB. Debug logging adds every request to the gateway and the details of iCloud and Keychain operations; turn it on to reproduce a problem, then off.")
            }
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share log and report", systemImage: "square.and.arrow.up") }
                }
                Button { copyReport() } label: { Label(copied ? "Report copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.clipboard") }
                #if os(macOS)
                Button { NSWorkspace.shared.activateFileViewerSelecting(Diag.files()) } label: { Label("Show log files in Finder", systemImage: "folder") }
                #endif
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear log", systemImage: "trash") }
                    .confirmationDialog("Clear the log?", isPresented: $confirmClear) { Button("Clear", role: .destructive) { Diag.clear(); refresh() } }
            } header: { SectionTitle("Export") } footer: {
                Text("The report lists app, device, servers (names and hosts only), iCloud state, the Files/Finder locations and the last lines of the log. API keys, tokens and passwords are never included.")
            }
            Section {
                Toggle(isOn: $showErrorsOnly) { Text("Errors and warnings only") }
                ScrollView(.horizontal) {
                    Text(visibleLines.isEmpty ? String(localized: "No log entries yet.") : visibleLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 420)
            } header: {
                HStack { SectionTitle("Latest entries"); Spacer(); Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }.buttonStyle(.plain) }
            }
        }
        .groupedFormStyle()
        .navigationTitle("Diagnostics")
        .inlineNavigationTitle()
        .task { refresh(); exportURL = await DiagnosticsReport.export(model: model) }
    }

    private var visibleLines: [String] {
        showErrorsOnly ? lines.filter { $0.contains(" ERROR ") || $0.contains(" WARN ") } : lines
    }

    private func refresh() {
        lines = Diag.tail(250)
        size = Diag.totalSize()
    }

    private func copyReport() {
        Clipboard.copy(DiagnosticsReport.text(model: model, server: nil, extra: []))
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// Builds the support report shared by the Diagnostics screen and the connection test.
enum DiagnosticsReport {
    @MainActor
    static func text(model: ServersModel, server: ServerConfig?, extra: [String]) -> String {
        let info = Bundle.main.infoDictionary
        var out: [String] = []
        out.append("Unraid Drive \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) · \(GatewayClient.clientDescription)")
        out.append("Date: \(Date().formatted(.iso8601))")
        out.append("Device id: \(DeviceIdentity.id.prefix(8))… (\(DeviceIdentity.isProvisional ? "provisional" : "registered"))")
        out.append("iCloud sync: \(model.cloud.enabled ? "on" : "off") · servers in iCloud: \(model.cloud.remoteServerCount) · debug log: \(Diag.debugEnabled ? "on" : "off")")
        out.append("App group container: \(AppGroup.containerURL != nil ? "available" : "MISSING")")
        let keychain = KeychainStore()
        for s in model.servers {
            if let server, server.id != s.id { continue }
            let m = model.maintenance[s.id] ?? model.storedMaintenance(s.id)
            let mm = m.map { "build \($0.build) gateway \($0.gatewayOK ? "ok" : "KO") location \($0.locationOK.map { $0 ? "ok" : "KO" } ?? "?") — \($0.detail)" } ?? "never"
            out.append("Server \(s.name): \(s.url.host ?? "?") · \(s.accessMode) · user \(s.username ?? "-") · secrets \(s.isDemo ? "n/a" : (keychain.hasSecrets(for: s.id) ? "present" : "MISSING")) · shares \(s.selectedShares?.count.description ?? "all") · maintenance: \(mm)")
        }
        if !extra.isEmpty { out.append(""); out += extra }
        out.append(""); out.append("Last log lines:")
        out += Diag.tail(80)
        return out.joined(separator: "\n")
    }

    /// The report plus the whole rotated log, as one text file ready for the share sheet.
    @MainActor
    static func export(model: ServersModel) async -> URL? {
        var header = text(model: model, server: nil, extra: [])
        do {
            let domains = try await NSFileProviderManager.domains()
            header += "\nLocations registered: " + (domains.isEmpty ? "none" : domains.map { d -> String in
                var s = "\(d.displayName) [\(d.identifier.rawValue.prefix(8))]"
                #if os(macOS)
                if d.isDisconnected { s += " disconnected" }
                #endif
                return s
            }.joined(separator: ", "))
        } catch {
            header += "\nLocations: cannot list — \(LocationErrorText.describe(error))"
        }
        return Diag.export(header: header)
    }
}

/// Pasteboard helper shared by the report buttons.
enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
