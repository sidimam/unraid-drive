import SwiftUI
import UnraidGatewayKit

struct AddServerView: View {
    @EnvironmentObject private var model: ServersModel
    @Environment(\.dismiss) private var dismiss
    /// When set, the view edits this server instead of creating a new one.
    var editing: ServerConfig? = nil
    @State private var name = ""
    @State private var urlText = ""
    @State private var apiKey = ""
    @State private var mode: Mode = .direct
    @State private var cfClientID = ""
    @State private var cfClientSecret = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: LoginResponse?
    @FocusState private var focusedField: Field?
    enum Field: Hashable { case name, url, apiKey, cfID, cfSecret }

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
                if editing != nil {
                    Section {
                        Label("Secrets are never shown back. Paste the API key again (and the service token, if any) to save.", systemImage: "info.circle")
                            .font(.callout)
                    }
                }
                Section("Server") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name).submitLabel(.next)
                        .onSubmit { focusedField = .url }
                    TextField("Gateway URL (https://nas.example.com)", text: $urlText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .url).submitLabel(.next)
                        .onSubmit { focusedField = .apiKey }
                }
                Section {
                    SecretField(title: "Unraid API key", text: $apiKey)
                        .focused($focusedField, equals: .apiKey)
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
                            .focused($focusedField, equals: .cfID)
                        SecretField(title: "CF-Access-Client-Secret", text: $cfClientSecret, monospaced: true)
                            .focused($focusedField, equals: .cfSecret)
                    }
                } header: { Text("Connection") } footer: {
                    if mode == .cloudflare {
                        Text("For gateways published through a Cloudflare Tunnel and protected by Zero Trust. Create a Service Token in Cloudflare Zero Trust › Access controls › Service credentials and add a policy with action Service Auth to the application. You can paste the lines exactly as Cloudflare shows them, labels included. The app sends the token with every request, like Unraid Deck.")
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
                if !model.hasDemo && editing == nil {
                    Section {
                        Button {
                            Task { await model.addDemo(); dismiss() }
                        } label: { Label("Try the demo server instead", systemImage: "sparkles") }
                    } footer: {
                        Text("No server yet? The demo adds sample shares that work offline, in this app and in the Files app.")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: cfClientID) { _, v in normaliseCloudflare(from: v, isSecretField: false) }
            .onChange(of: cfClientSecret) { _, v in normaliseCloudflare(from: v, isSecretField: true) }
            .onAppear {
                if let e = editing, name.isEmpty, urlText.isEmpty {
                    name = e.name; urlText = e.url.absoluteString
                    mode = e.accessMode == .cloudflareAccess ? .cloudflare : .direct
                }
            }
            .navigationTitle(editing == nil ? "Add server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Connecting…" : (editing == nil ? "Connect" : "Save")) { Task { await connect() } }
                        .disabled(busy || !canConnect)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    /// Accept whatever the user pasted from the Cloudflare dashboard: a bare value, a
    /// `CF-Access-Client-Id: …` line, or both lines at once, and put each part in its field.
    private func normaliseCloudflare(from text: String, isSecretField: Bool) {
        let lower = text.lowercased()
        guard text.contains(where: \.isNewline) || lower.contains("cf-access-client") else { return }
        let parsed = CloudflareServiceToken.parse(text)
        if let id = parsed.clientID { cfClientID = id } else if isSecretField == false { cfClientID = "" }
        if let secret = parsed.clientSecret { cfClientSecret = secret } else if isSecretField { cfClientSecret = "" }
    }

    private func connect() async {
        guard let url else { return }
        busy = true; error = nil
        defer { busy = false }
        // Pasted values often carry a trailing newline; a newline inside an HTTP header makes
        // URLSession refuse the request, which surfaces as "cannot reach the gateway".
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline } }
        let token = mode == .cloudflare
            ? CloudflareServiceToken(clientID: clean(cfClientID), clientSecret: clean(cfClientSecret))
            : nil
        do {
            let finalName = name.isEmpty ? (url.host ?? "Unraid") : name
            let login: LoginResponse
            if let editing {
                login = try await model.update(editing, name: finalName, url: url, apiKey: clean(apiKey), cloudflare: token)
            } else {
                login = try await model.add(name: finalName, url: url, apiKey: clean(apiKey), cloudflare: token)
            }
            result = login
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
