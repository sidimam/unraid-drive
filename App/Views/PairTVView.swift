import SwiftUI
import UnraidGatewayKit

/// Sends a server and its secrets to an Apple TV showing a pairing code (encrypted with the code,
/// through iCloud Key-Value Storage; the blob is deleted by the TV as soon as it is read).
struct PairTVView: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var serverID: String = ""
    @State private var sent = false
    @State private var error: String?
    private let keychain = KeychainStore()

    private var candidates: [ServerConfig] { model.servers.filter { !$0.isDemo } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("On the Apple TV open Unraid Drive: it shows a 6-digit code. Enter it here and choose the server to send. The credentials travel encrypted with the code; the TV connects through your unraid-gateway with your own permissions.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Code shown on the TV", text: $code).monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Picker("Server", selection: $serverID) { ForEach(candidates) { s in Text(s.name).tag(s.id) } }
                } header: { SectionTitle("Pair an Apple TV") }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
                if sent { Section { Label("Sent. The TV picks it up within a few seconds.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            }
            .groupedFormStyle()
            .navigationTitle("Pair an Apple TV")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Send") { send() }.disabled(code.filter(\.isNumber).count != 6 || serverID.isEmpty) }
            }
            .onAppear { if serverID.isEmpty { serverID = candidates.first?.id ?? "" } }
        }
        .sheetFrame()
    }

    private func send() {
        guard let server = candidates.first(where: { $0.id == serverID }) else { return }
        guard let key = keychain.apiKey(for: server.id) else { error = String(localized: "The API key of this server is missing on this device."); return }
        let cf = keychain.cloudflareToken(for: server.id); let u = keychain.userCredentials(for: server.id)
        let payload = PairingPayload(server: server, apiKey: key, cloudflare: cf, username: u?.username, password: u?.password)
        do {
            let digits = code.filter(\.isNumber)
            let blob = try TVPairing.encrypt(payload, code: digits)
            let kvs = NSUbiquitousKeyValueStore.default
            kvs.set(blob, forKey: TVPairing.kvsKey(digits)); kvs.synchronize()
            sent = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
