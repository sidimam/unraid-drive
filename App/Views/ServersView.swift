import SwiftUI
import UnraidGatewayKit

struct ServersView: View {
    @EnvironmentObject private var model: ServersModel
    @EnvironmentObject private var cloud: CloudSync
    @State private var adding = false
    @State private var showSettings = false
    @State private var showWalkthrough = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("walkthrough.seen") private var walkthroughSeen = false
    /// Navigation path; `-openServer` as a launch argument opens the first server (screenshot automation).
    @State private var path: [ServerConfig] = []

    @ViewBuilder private var restoreBanner: some View {
        if cloud.shouldOfferRestore(localServers: model.servers) {
            Section {
                Button {
                    Task { await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains() }
                } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "icloud.and.arrow.down") }
            } footer: { Text("A configuration saved by Unraid Drive was found in your iCloud account.") }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No servers", systemImage: "externaldrive.badge.plus")
                    } description: {
                        Text("Add your Unraid server through its unraid-gateway URL and an Unraid API key. Its shares will appear in the Files app.")
                    } actions: {
                        Button("Add server") { adding = true }.buttonStyle(.borderedProminent)
                        if cloud.remoteServerCount > 0 {
                            Button("Restore \(cloud.remoteServerCount) server(s) from iCloud") { Task { await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains() } }.buttonStyle(.bordered)
                        }
                        Button("Try the demo") { Task { await model.addDemo() } }.buttonStyle(.bordered)
                    }
                } else {
                    List {
                        restoreBanner
                        ForEach(model.servers) { server in
                            NavigationLink(value: server) {
                                HStack {
                                    Image(systemName: server.isDemo ? "sparkles" : (server.accessMode == .cloudflareAccess ? "cloud.fill" : "externaldrive.fill")).foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name).font(.headline)
                                        Text(server.isDemo ? "Sample data, offline" : (server.username.map { "\($0) · " } ?? "") + server.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            let victims = idx.map { model.servers[$0] }
                            Task { for s in victims { await model.remove(s) } }
                        }
                        Section {
                            Button { adding = true } label: { Label("Add another server", systemImage: "plus.circle") }
                        } footer: {
                            Text("Every server you add becomes its own location in the Files app. Swipe left on a server to remove it.")
                        }
                    }
                }
            }
            .navigationTitle("Unraid Drive")
            .navigationDestination(for: ServerConfig.self) { ServerDetailView(server: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showWalkthrough = true } label: { Image(systemName: "questionmark.circle") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { adding && sizeClass == .compact }, set: { adding = $0 })) { AddServerView() }
            .sheet(isPresented: Binding(get: { adding && sizeClass != .compact }, set: { adding = $0 })) {
                AddServerView().presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showWalkthrough, onDismiss: { walkthroughSeen = true }) {
                WalkthroughView(onTryDemo: model.hasDemo ? nil : { Task { await model.addDemo() } })
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-openServer"), let first = model.servers.first {
                    walkthroughSeen = true
                    path = [first]
                } else if !walkthroughSeen {
                    showWalkthrough = true
                }
            }
        }
    }
}
