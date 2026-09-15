import SwiftUI
import UnraidGatewayKit

/// Apple TV has no share sheet: the log is shown here, debug logging can be switched on, and the
/// report + log can be sent to the gateway as a text file in the first writable share
/// (`<share>/Unraid Drive/Logs/`), from where any other device picks it up.
struct TVDiagnosticsView: View {
    @EnvironmentObject private var model: TVModel
    let server: ServerConfig
    @State private var debug = Diag.debugEnabled
    @State private var lines: [String] = []
    @State private var status: String?
    @State private var sending = false

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            List {
                Section {
                    Toggle(isOn: $debug) { TVMenuRow(title: "Debug logging", symbol: "ladybug") }
                        .onChange(of: debug) { _, v in Diag.debugEnabled = v; refresh() }
                    Button { Task { await send() } } label: { TVMenuRow(title: sending ? "Sending…" : "Send log to the server", symbol: "square.and.arrow.up") }.disabled(sending || server.isDemo)
                    Button { refresh() } label: { TVMenuRow(title: "Refresh", symbol: "arrow.clockwise") }
                    Button(role: .destructive) { Diag.clear(); refresh() } label: { TVMenuRow(title: "Clear log", symbol: "trash", destructive: true) }
                } footer: {
                    Text(status ?? String(localized: "The log is written by this app and rotates at \(Diag.maxFiles) × \(Diag.maxFileSize / 1_000_000) MB. Debug logging adds every request to the gateway; turn it on to reproduce a problem, then off."))
                }
            }
            .frame(width: 620)
            ScrollView {
                Text(lines.isEmpty ? String(localized: "No log entries yet.") : lines.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .focusable()
        }
        .padding(.horizontal, 60)
        .navigationTitle(Text("Diagnostics") + Text(verbatim: " · \(server.name)"))
        .onAppear { refresh() }
    }

    private func refresh() { lines = Diag.tail(120) }

    private func send() async {
        guard let client = model.client(for: server) else { status = String(localized: "No credentials for this server on the TV."); return }
        sending = true; defer { sending = false }
        do {
            let login = try await client.login()
            let shares = try await client.list("/").entries.filter(\.isDirectory)
            guard let share = shares.first(where: { (login.shares?[$0.name] ?? "rw") == "rw" }) ?? shares.first else {
                status = String(localized: "No share available for the upload."); return
            }
            let info = Bundle.main.infoDictionary
            var header = "Unraid Drive \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) · \(GatewayClient.clientDescription)\n"
            header += "Date: \(Date().formatted(.iso8601)) · device id \(DeviceIdentity.id.prefix(8))… · debug log \(Diag.debugEnabled ? "on" : "off")\n"
            header += "Servers on this TV: " + model.servers.map { "\($0.name) (\($0.url.host ?? "?"), \($0.accessMode))" }.joined(separator: ", ")
            guard let file = Diag.export(header: header) else { status = String(localized: "Could not build the report."); return }
            let dir = GatewayPath.join(share.path, "Unraid Drive/Logs")
            _ = try? await client.mkdir(dir, parents: true)
            let name = "AppleTV-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")).log"
            _ = try await client.upload(fileURL: file, to: GatewayPath.join(dir, name))
            status = String(localized: "Sent to \(share.name)/Unraid Drive/Logs/\(name)")
            Diag.info("diagnostics", "log uploaded to \(dir)/\(name)")
        } catch {
            status = error.localizedDescription
            Diag.error("diagnostics", "log upload", error)
        }
    }
}
