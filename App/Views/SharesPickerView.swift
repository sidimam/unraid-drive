import SwiftUI
import UnraidGatewayKit
import os

/// The toggles for one server: "All shares" plus one row per share the gateway exposes to this
/// user. Used in the server page, in Settings and in the walkthrough. The choice is stored with
/// the server and travels with the iCloud configuration and the Apple TV pairing.
struct SharesToggleList: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @State private var shares: [String] = []
    @State private var error: String?
    @State private var loading = true

    private var current: ServerConfig { model.current(server) }
    private var allSelected: Bool { current.selectedShares == nil }

    var body: some View {
        Toggle("All shares", isOn: Binding(get: { allSelected }, set: { on in
            let value: [String]? = on ? nil : shares
            Task { await model.setSelectedShares(server, value) }
        }))
        // `.task` lives on a view that always exists: on an empty ForEach it would never run.
        .task { await load() }
        if loading {
            HStack { ProgressView(); Text("Loading shares…") }
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            Button { loading = true; Task { await load() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
        } else if shares.isEmpty {
            Text("No shares are visible for this user.").foregroundStyle(.secondary)
        }
        ForEach(shares, id: \.self) { share in
            Toggle(isOn: Binding(get: { current.showsShare(share) }, set: { on in toggle(share, on) })) {
                Label(share, systemImage: "externaldrive")
            }
            .disabled(allSelected)
        }
    }

    private func toggle(_ share: String, _ on: Bool) {
        var selected = current.selectedShares ?? shares
        selected.removeAll { $0.lowercased() == share.lowercased() }
        if on { selected.append(share) }
        // Keep the gateway's order so the list reads the same everywhere.
        let ordered = shares.filter { s in selected.contains { $0.lowercased() == s.lowercased() } }
        Task { await model.setSelectedShares(server, ordered) }
    }

    private func load() async {
        guard let client = model.client(for: server) else {
            // Right after an iCloud restore the secrets may still be on their way through iCloud Keychain.
            error = String(localized: "Credentials not available yet. After an iCloud restore they arrive through iCloud Keychain within a minute; try again.")
            loading = false; return
        }
        do {
            let listed = try await client.list("/").entries.filter(\.isDirectory).map(\.name)
            // Shares chosen earlier that the gateway no longer exposes stay listed so they can be unticked.
            let stale = (current.selectedShares ?? []).filter { s in !listed.contains { $0.lowercased() == s.lowercased() } }
            shares = listed + stale
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

/// Full page for one server (server details, Settings, right after adding a server).
struct SharesPickerView: View {
    let server: ServerConfig
    /// Shown after adding a server: a Done button closes the whole sheet.
    var onDone: (() -> Void)? = nil

    var body: some View {
        Form {
            if onDone != nil {
                Section { Text("Choose which shares to show. You can change this later in the server's details or in Settings.") }
            }
            Section {
                SharesToggleList(server: server)
            } footer: {
                #if os(macOS)
                Text("Only the selected shares appear in the Finder, in Shortcuts and on Apple TV. Your Unraid user's permissions still apply on the gateway.")
                #else
                Text("Only the selected shares appear in the Files app, in Shortcuts and on Apple TV. Your Unraid user's permissions still apply on the gateway.")
                #endif
            }
        }
        .groupedFormStyle()
        .navigationTitle("Shares to show")
        .inlineNavigationTitle()
        .toolbar {
            if let onDone { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() } } }
        }
    }
}

/// Settings › Shares to show: one entry per server.
struct SharesSettingsView: View {
    @EnvironmentObject private var model: ServersModel

    var body: some View {
        Form {
            Section {
                if model.servers.isEmpty {
                    Text("No server yet. Add one from the main screen; you will choose its shares right after connecting.").foregroundStyle(.secondary)
                }
                ForEach(model.servers) { s in
                    NavigationLink { SharesPickerView(server: s) } label: {
                        LabeledContent {
                            Text(s.selectedShares == nil ? String(localized: "All shares") : String(localized: "\(s.selectedShares?.count ?? 0) shares"))
                        } label: { Label(s.name, systemImage: s.isDemo ? "sparkles" : "externaldrive.connected.to.line.below") }
                    }
                }
            } footer: {
                Text("Only the selected shares appear in the Files app, in Shortcuts and on Apple TV. Your Unraid user's permissions still apply on the gateway.")
            }
        }
        .groupedFormStyle()
        .navigationTitle("Shares to show")
        .inlineNavigationTitle()
    }
}

extension ServerConfig {
    /// "3 of 5 shares" style summary for lists; nil when every share is shown.
    func sharesSummary(total: Int?) -> String? {
        guard let selected = selectedShares else { return nil }
        if let total { return String(localized: "\(selected.count) of \(total) shares") }
        return String(localized: "\(selected.count) shares")
    }
}
