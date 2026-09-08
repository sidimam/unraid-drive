import SwiftUI

/// First-launch walkthrough, also reachable from the help button.
struct WalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    var onTryDemo: (() -> Void)?

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        let link: (String, URL)?
    }

    private let pages: [Page] = [
        Page(icon: "externaldrive.connected.to.line.below", title: "Your Unraid shares in Files",
             text: "Unraid Drive adds your Unraid shares to the Files app next to iCloud Drive. Open, save, move and share files from any app, at home or on 5G, without a VPN.", link: nil),
        Page(icon: "shippingbox", title: "1 · Install the gateway",
             text: "On Unraid, add the unraid-gateway container from the template URL in the project README. Map the shares you want on your phone under /data/<name>. Nothing else runs on the server.",
             link: ("github.com/sidimam/unraid-gateway", URL(string: "https://github.com/sidimam/unraid-gateway")!)),
        Page(icon: "key", title: "2 · Create an API key",
             text: "In the Unraid WebGUI open Settings › Management Access › API Keys and add a key. VIEWER is enough for files and the dashboard. The key never leaves your device except to your own gateway.", link: nil),
        Page(icon: "cloud", title: "3 · Reach it from outside",
             text: "Publish the gateway port through a Cloudflare Tunnel (works behind CGNAT, free) or a reverse proxy with a valid certificate. Optionally protect it with Cloudflare Zero Trust and a Service Token: the app supports it.", link: nil),
        Page(icon: "folder.badge.plus", title: "4 · Add the server",
             text: "Tap + , enter the gateway URL and the API key, connect. The server appears in the Files app under Unraid Drive. Curious first? Try the demo server: sample files, no setup.", link: nil),
    ]
    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack {
                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 20) {
                            Image(systemName: p.icon).font(.system(size: 64)).foregroundStyle(.tint).padding(.top, 24)
                            Text(p.title).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(p.text).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
                            if let (label, url) = p.link { Link(label, destination: url).font(.callout) }
                            Spacer()
                        }.tag(i).padding()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                HStack {
                    if let onTryDemo, index == pages.count - 1 {
                        Button("Try the demo") { onTryDemo(); dismiss() }.buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(index == pages.count - 1 ? "Done" : "Next") {
                        if index < pages.count - 1 { withAnimation { index += 1 } } else { dismiss() }
                    }.buttonStyle(.borderedProminent)
                }.padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } } }
        }
    }
}
