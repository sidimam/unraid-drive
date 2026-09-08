import SwiftUI
import UnraidGatewayKit

struct ServersView: View {
    @EnvironmentObject private var model: ServersModel
    @State private var adding = false
    @State private var showWalkthrough = false
    @AppStorage("walkthrough.seen") private var walkthroughSeen = false
    /// Navigation path; `-openServer` as a launch argument opens the first server (screenshot automation).
    @State private var path: [ServerConfig] = []

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
                        Button("Try the demo") { Task { await model.addDemo() } }.buttonStyle(.bordered)
                    }
                } else {
                    List {
                        ForEach(model.servers) { server in
                            NavigationLink(value: server) {
                                HStack {
                                    Image(systemName: server.isDemo ? "sparkles" : (server.accessMode == .cloudflareAccess ? "cloud.fill" : "externaldrive.fill")).foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name).font(.headline)
                                        Text(server.isDemo ? "Sample data, offline" : server.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            let victims = idx.map { model.servers[$0] }
                            Task { for s in victims { await model.remove(s) } }
                        }
                    }
                }
            }
            .navigationTitle("Unraid Drive")
            .navigationDestination(for: ServerConfig.self) { ServerDetailView(server: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showWalkthrough = true } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $adding) { AddServerView() }
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
