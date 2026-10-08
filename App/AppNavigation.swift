import Foundation

/// Cross-view navigation requests (build 42): the explorer's gear, the Mac menu bar panel and the
/// Home Screen quick actions all land in the single Settings sheet owned by `RootView`.
enum AppNavigation {
    /// Open Settings (profiles + app settings).
    static let openSettings = Notification.Name("com.sdimambro.unraid-drive.openSettings")
    /// Open Settings and present the "Add a profile" form.
    static let addProfile = Notification.Name("com.sdimambro.unraid-drive.addProfile")
    /// Close Settings and show the folders of the current profile.
    static let showFolders = Notification.Name("com.sdimambro.unraid-drive.showFolders")
}
