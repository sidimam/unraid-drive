import SwiftUI
import UnraidGatewayKit

/// Walkthrough shown at the first launch and after every update (keyed by the build number),
/// also reachable from the help button. Presents the features, offers iCloud (restore or sync)
/// and asks for the notification permission; every step can be skipped.
struct WalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloud: CloudSync
    @EnvironmentObject private var model: ServersModel
    var onTryDemo: (() -> Void)?

    /// Build number for which the walkthrough was last completed or skipped.
    static let seenBuildKey = "walkthrough.seenBuild"
    static var currentBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
    static var shouldShow: Bool { UserDefaults.standard.string(forKey: seenBuildKey) != currentBuild }
    static func markSeen() { UserDefaults.standard.set(currentBuild, forKey: seenBuildKey) }

    private enum Kind { case info, icloud, notifications, shares }
    private struct Page: Identifiable {
        let id = UUID()
        let kind: Kind
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var link: (String, URL)? = nil
    }

    /// Fresh install (or reinstall) with a configuration waiting in iCloud: the restore comes first.
    @State private var restoreFirst = false

    private var pages: [Page] {
        let icloudPage = restoreFirst
            ? Page(kind: .icloud, icon: "icloud.and.arrow.down", title: "Configuration found in iCloud",
                   text: "Another device (or this one, before a reinstall) saved \(cloud.remoteServerCount) server(s) in iCloud. Restore them here: the list arrives from iCloud, the API keys, Cloudflare service tokens and Unraid passwords from iCloud Keychain, and this device registers itself on each gateway again.")
            : Page(kind: .icloud, icon: "icloud", title: "Your configuration in iCloud",
                   text: "One backup shared by iPhone, iPad, Vision Pro and Mac: the server list in iCloud and the secrets in iCloud Keychain, end-to-end encrypted. You can turn it on later in Settings › iCloud.")
        var p: [Page] = []
        if restoreFirst { p.append(icloudPage) }
        p += [
            Page(kind: .info, icon: "externaldrive.connected.to.line.below", title: "Your Unraid shares in Files and in the Finder",
                 text: "Unraid Drive adds your Unraid shares to the Files app on iPhone, iPad and Vision Pro and to the Finder sidebar on the Mac, next to iCloud Drive. Open, save, move and share files from any app, at home or away, over HTTPS."),
            Page(kind: .info, icon: "sparkles", title: "What's new in this version",
                 text: "Restore first: on a new or reinstalled device the walkthrough finds the configuration saved in iCloud, restores it and registers the device on the gateways again; the Apple TV shows what is waiting in iCloud and receives every server with one pairing code. Clearer errors when a video cannot stream; Rename and New folder on Apple TV."),
        ]
        if !restoreFirst { p.append(icloudPage) }
        p += [
            Page(kind: .shares, icon: "externaldrive.badge.checkmark", title: "Choose the shares to show",
                 text: "For each server, tick the shares you want in the Files app, the Finder, Shortcuts and on Apple TV. You can change this any time in Settings › Shares to show."),
            Page(kind: .notifications, icon: "bell.badge", title: "Stay informed",
                 text: "Unraid Drive can tell you when a gateway is unreachable and when a file could not be uploaded or downloaded. You choose what to allow in the system Settings at any time."),
            Page(kind: .info, icon: "shippingbox", title: "1 · Install the gateway",
                 text: "On Unraid, add the unraid-gateway container from Community Applications (or the template URL in the project README). Map the shares you want under /data/<name>. Nothing else runs on the server.",
                 link: ("github.com/sidimam/unraid-gateway", URL(string: "https://github.com/sidimam/unraid-gateway")!)),
            Page(kind: .info, icon: "key", title: "2 · Create an API key",
                 text: "In the Unraid WebGUI open Settings › Management Access › API Keys and add a key. VIEWER is enough for files and the dashboard. The key never leaves your device except to your own gateway."),
            Page(kind: .info, icon: "cloud", title: "3 · Reach it from outside",
                 text: "Publish the gateway port through Cloudflare (works behind CGNAT, free) or a reverse proxy with a valid certificate. Optionally protect it with Cloudflare Zero Trust and a Service Token: the app supports it."),
            Page(kind: .info, icon: "folder.badge.plus", title: "4 · Add the server",
                 text: "Tap + , enter the gateway URL and the API key, connect. The server appears in the Files app and in the Finder under Unraid Drive. Curious first? Try the demo server: sample files, no setup."),
        ]
        return p
    }
    @State private var index = 0
    @State private var busy = false
    @State private var restored = false
    @State private var notificationStatus: UNAuthorizationStatusBox = .unknown

    private enum UNAuthorizationStatusBox { case unknown, allowed, denied, notAsked }

    private func page(_ p: Page) -> some View {
        VStack(spacing: 20) {
            Image(systemName: p.icon).font(.largeTitle).imageScale(.large).foregroundStyle(.tint).padding(.top, 24)
            Text(p.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(p.text).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
            if let (label, url) = p.link { Link(label, destination: url).font(.callout) }
            switch p.kind {
            case .icloud: icloudControls
            case .notifications: notificationControls
            case .shares: sharesControls
            case .info: EmptyView()
            }
            Spacer()
        }.padding()
    }

    @ViewBuilder private var sharesControls: some View {
        if model.servers.isEmpty {
            Text("Add a server first: you will choose its shares right after connecting.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.servers) { s in
                        Text(s.name).font(.headline).padding(.top, 8)
                        SharesToggleList(server: s)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 320)
        }
    }

    @ViewBuilder private var icloudControls: some View {
        if cloud.enabled {
            Label(restored ? "Configuration restored: \(model.servers.filter { !$0.isDemo }.count) server(s)." : "iCloud sync is on.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if restored { registrationStatus }
        } else if cloud.remoteServerCount > 0 {
            if busy { ProgressView("Restoring…") }
            Button {
                Task {
                    busy = true
                    await cloud.restoreFromCloud(); await model.reloadAndRegisterDomains()
                    restored = true; busy = false
                    // Register this installation on every gateway (the secrets may still be arriving).
                    await model.registerRestoredDevices()
                }
            } label: { Label("Restore \(cloud.remoteServerCount) server(s) from iCloud", systemImage: "arrow.down.circle") }
            .buttonStyle(.borderedProminent).disabled(busy)
            Text(cloud.remoteServers.map(\.name).joined(separator: " · ")).font(.callout).foregroundStyle(.tint).multilineTextAlignment(.center).padding(.horizontal)
            Text("A configuration saved by Unraid Drive on another device was found. Restoring turns sync on; the secrets arrive through iCloud Keychain and this device is registered on each gateway again.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        } else {
            Button {
                Task { busy = true; await cloud.setEnabled(true); busy = false }
            } label: { Label("Enable iCloud sync", systemImage: "icloud.and.arrow.up") }
            .buttonStyle(.borderedProminent).disabled(busy)
            Text("No backup found yet. Turning sync on saves this device's servers for the others.").font(.footnote).foregroundStyle(.secondary)
        }
        if let e = cloud.lastError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
    }

    /// After a restore: one line per server with the outcome of the registration on its gateway.
    @ViewBuilder private var registrationStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.servers.filter { !$0.isDemo }) { s in
                HStack(spacing: 8) {
                    switch model.restoreRegistration[s.id] {
                    case .registered: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(s.name); Text("registered on the gateway").foregroundStyle(.secondary)
                    case .failed(let why): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(s.name); Text(why).foregroundStyle(.secondary).lineLimit(3)
                    case .waitingSecrets: ProgressView().controlSize(.small); Text(s.name); Text("waiting for the credentials from iCloud Keychain…").foregroundStyle(.secondary)
                    case nil: Image(systemName: "circle").foregroundStyle(.secondary); Text(s.name)
                    }
                }.font(.footnote)
            }
        }.padding(.horizontal)
    }

    @ViewBuilder private var notificationControls: some View {
        switch notificationStatus {
        case .allowed: Label("Notifications are allowed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Label("Notifications are off for Unraid Drive.", systemImage: "bell.slash").foregroundStyle(.secondary)
            Button { AppNotifications.openSystemSettings() } label: { Label("Open notification settings", systemImage: "gearshape") }.buttonStyle(.bordered)
        default:
            Button {
                Task { _ = await AppNotifications.requestAuthorization(); await refreshNotificationStatus() }
            } label: { Label("Allow notifications", systemImage: "bell.badge") }.buttonStyle(.borderedProminent)
        }
    }

    private func refreshNotificationStatus() async {
        switch await AppNotifications.status() {
        case .authorized, .provisional, .ephemeral: notificationStatus = .allowed
        case .denied: notificationStatus = .denied
        default: notificationStatus = .notAsked
        }
    }

    private func finish() { Self.markSeen(); dismiss() }

    var body: some View {
        let pages = self.pages
        NavigationStack {
            VStack {
                #if os(macOS)
                page(pages[index]).id(index).frame(minWidth: 480, minHeight: 300)
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle().fill(i == index ? AppIconColor.currentTint : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
                #else
                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, p in page(p).tag(i) }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                #endif

                HStack {
                    #if os(macOS)
                    if index > 0 { Button("Back") { withAnimation { index -= 1 } } }
                    #endif
                    if let onTryDemo {
                        Button("Try the demo") { onTryDemo(); finish() }.buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(index == pages.count - 1 ? "Done" : "Next") {
                        if index < pages.count - 1 { withAnimation { index += 1 } } else { finish() }
                    }.buttonStyle(.borderedProminent)
                }.padding()
            }
            .navigationTitle("Welcome")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip") { finish() } } }
            .task {
                await refreshNotificationStatus()
                // Nothing local, something in iCloud: put the restore first (evaluated once, so the
                // page order does not jump while the user reads).
                restoreFirst = cloud.shouldOfferRestore(localServers: model.servers)
                _ = await cloud.pull()
            }
        }
        .sheetFrame()
    }
}
