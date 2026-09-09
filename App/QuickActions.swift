import SwiftUI
#if os(iOS)
import UIKit

/// Home Screen quick actions (long-press on the icon). Static items are declared in Info.plist
/// (UIApplicationShortcutItems); the scene delegate turns them into a notification the UI observes.
enum QuickAction: String, CaseIterable {
    case openFiles = "com.sdimambro.unraid-drive.openFiles"
    case testConnection = "com.sdimambro.unraid-drive.testConnection"
    case addServer = "com.sdimambro.unraid-drive.addServer"

    static let notification = Notification.Name("QuickAction")

    static func post(_ item: UIApplicationShortcutItem) {
        guard let action = QuickAction(rawValue: item.type) else { return }
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["action": action.rawValue])
    }
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            // Cold start: the UI is not up yet; deliver once it has appeared.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { QuickAction.post(item) }
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        QuickAction.post(shortcutItem)
        completionHandler(true)
    }
}
#endif
