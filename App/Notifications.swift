import Foundation
import UserNotifications
import UnraidGatewayKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Local notifications: the app tells the user when a gateway cannot be reached and when the
/// Files app / Finder could not upload or download something. No in-app switches: the user
/// decides in the system Settings, which the "Notifications ›" row opens.
enum AppNotifications {
    static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Opens the app's page in the system notification settings.
    static func openSystemSettings() {
        #if os(macOS)
        let id = Bundle.main.bundleIdentifier ?? "com.sdimambro.unraid-drive"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }

    /// Posts one notification; the identifier replaces an earlier one with the same id.
    static func post(id: String, title: String, body: String, thread: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default; content.threadIdentifier = thread
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// Reachability of every configured gateway. Notifies on the transition reachable → unreachable
/// (once, not on every check) and again when the server is back.
enum HealthMonitor {
    private static func key(_ id: String) -> String { "health.down." + id }

    @MainActor
    static func check(_ servers: [ServerConfig], client: (ServerConfig) -> GatewayClient?) async {
        guard await AppNotifications.status() == .authorized else { return }
        for s in servers where !s.isDemo {
            guard let c = client(s) else { continue }
            var failure: String?
            do { _ = try await c.health() } catch { failure = error.localizedDescription }
            let wasDown = AppGroup.defaults.bool(forKey: key(s.id))
            if let failure, !wasDown {
                AppGroup.defaults.set(true, forKey: key(s.id))
                AppNotifications.post(id: "health." + s.id,
                                      title: String(localized: "Cannot reach \(s.name)"),
                                      body: String(localized: "unraid-gateway did not answer: \(failure). Files already downloaded stay available; changes will sync when the server is back."),
                                      thread: "health")
            } else if failure == nil, wasDown {
                AppGroup.defaults.set(false, forKey: key(s.id))
                AppNotifications.post(id: "health." + s.id,
                                      title: String(localized: "\(s.name) is reachable again"),
                                      body: String(localized: "The connection to unraid-gateway is back; the Files location resumes syncing."),
                                      thread: "health")
            }
        }
    }
}

/// Turns failed operations recorded by the File Provider extension (ActivityLog) into
/// notifications, once each (the last handled event id is remembered).
enum ActivityAlerts {
    private static let lastKey = "activity.lastNotified"

    static func process(serverName: (String) -> String?) async {
        guard await AppNotifications.status() == .authorized else { return }
        let events = ActivityLog.recent().reversed()           // oldest first
        let last = AppGroup.defaults.string(forKey: lastKey)
        var seenLast = last == nil
        var newest: String?
        for e in events {
            if !seenLast { if e.id.uuidString == last { seenLast = true }; continue }
            newest = e.id.uuidString
            guard e.failed, let err = e.error else { continue }
            let name = serverName(e.serverID) ?? "Unraid Drive"
            let what: String
            switch e.kind {
            case .download: what = String(localized: "Could not download \(e.name)")
            case .upload, .create: what = String(localized: "Could not upload \(e.name)")
            case .folder: what = String(localized: "Could not create the folder \(e.name)")
            case .move: what = String(localized: "Could not move or rename \(e.name)")
            case .delete: what = String(localized: "Could not delete \(e.name)")
            }
            AppNotifications.post(id: "activity." + e.id.uuidString, title: what, body: "\(name) · \(err)", thread: "activity")
        }
        if !seenLast, let l = events.last { newest = l.id.uuidString }   // the remembered id is gone: restart from the newest
        if let newest { AppGroup.defaults.set(newest, forKey: lastKey) }
    }
}
