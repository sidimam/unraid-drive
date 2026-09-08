import SwiftUI
import UnraidGatewayKit

struct AddServerView: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""
    @State private var apiKey = ""
    @State private var mode: Mode = .direct
    @State private var cfClientID = ""
    @State private var cfClientSecret = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: LoginResponse?

    enum Mode: String, CaseIterable, Identifiable {
        case direct = "Direct"
        case cloudflare = "Cloudflare Access"
        var id: String { rawValue }
    }

    private var url: URL? {
        var t = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), let scheme = u.scheme, ["http", "https"].contains(scheme), u.host != nil else { return nil }
        return u
    }
    private var canConnect: Bool {
        url != nil && !apiKey.isEmpty && (mode == .direct || (!cfClientID.isEmpty && !cfClientSecret.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    TextField("Gateway URL (https://nas.example.com)", text: $urlText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    SecureField("Unraid API key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Authentication") } footer: {
                    Text("Create the key in Unraid under Settings › Management Access › API Keys. It is stored in this device's Keychain and sent only to your gateway.")
                }
                Section {
                    Picker("Connection", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if mode == .cloudflare {
                        TextField("CF-Access-Client-Id", text: $cfClientID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().font(.callout.monospaced())
                        SecureField("CF-Access-Client-Secret", text: $cfClientSecret)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: { Text("Connection") } footer: {
                    if mode == .cloudflare {
                        Text("For gateways published through a Cloudflare Tunnel and protected by Zero Trust. Create a Service Token in Cloudflare Zero Trust › Access › Service Auth and allow it in the application's policy; the app sends it with every request, the same way Unraid Deck does.")
                    } else {
                        Text("Plain HTTPS to the gateway: a LAN address, a reverse proxy with a certificate, or a Cloudflare Tunnel hostname without Access.")
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                if let result {
                    Section("Connected") {
                        LabeledContent("Identity", value: result.identity.name ?? "api key")
                        LabeledContent("Roles", value: (result.identity.roles ?? []).joined(separator: ", "))
                        if result.readOnly { Label("Gateway is read-only", systemImage: "lock") }
                    }
                }
                if !model.hasDemo {
                    Section {
                        Button {
                            Task { await model.addDemo(); dismiss() }
                        } label: { Label("Try the demo server instead", systemImage: "sparkles") }
                    } footer: {
                        Text("No server yet? The demo adds sample shares that work offline, in this app and in the Files app.")
                    }
                }
            }
            .navigationTitle("Add server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }
                        .disabled(busy || !canConnect)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private func connect() async {
        guard let url else { return }
        busy = true; error = nil
        defer { busy = false }
        let token = mode == .cloudflare
            ? CloudflareServiceToken(clientID: cfClientID.trimmingCharacters(in: .whitespaces), clientSecret: cfClientSecret.trimmingCharacters(in: .whitespaces))
            : nil
        do {
            let login = try await model.add(name: name.isEmpty ? (url.host ?? "Unraid") : name, url: url,
                                            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), cloudflare: token)
            result = login
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
