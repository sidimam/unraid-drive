import Foundation
import UnraidGatewayKit

/// 1.5 Continuity: Handoff of "browsing a folder" between iPhone, iPad, Mac and Vision Pro, and the
/// optional "open where I left off on the other device" through iCloud key-value storage.
enum Continuity {
    static let browseActivity = "com.sdimambro.unraid-drive.browse"
    static let resumeKey = "continuity.resume"
    private static let kvsKey = "continuity.lastFolder.v1"

    static var resumeEnabled: Bool { AppGroup.defaults.bool(forKey: resumeKey) }

    static func fill(_ a: NSUserActivity, server: ServerConfig, path: String) {
        a.title = path == "/" ? server.name : "\(GatewayPath.name(path)) — \(server.name)"
        a.userInfo = ["server": server.id, "path": path]
        a.requiredUserInfoKeys = ["server", "path"]
        a.isEligibleForHandoff = true
        a.isEligibleForSearch = false
        #if !os(macOS)
        a.isEligibleForPrediction = false
        #endif
        a.targetContentIdentifier = server.id + path
    }

    static func read(_ a: NSUserActivity) -> (String, String)? {
        guard let s = a.userInfo?["server"] as? String, let p = a.userInfo?["path"] as? String else { return nil }
        return (s, p)
    }

    /// Every ancestor of `path` (deepest last), so Back walks up the folders.
    static func chain(_ path: String) -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var out: [String] = []
        var cur = ""
        for p in parts { cur += "/" + p; out.append(cur) }
        return out
    }

    /// Remembered in iCloud KVS with this device's id, so another device can open the same folder.
    static func rememberLastFolder(server: ServerConfig, path: String) {
        guard !server.isDemo, NSUbiquitousKeyValueStore.default.dictionaryRepresentation.count >= 0 else { return }
        let rec: [String: Any] = ["server": server.id, "path": path, "device": DeviceIdentity.id, "at": Date().timeIntervalSince1970]
        NSUbiquitousKeyValueStore.default.set(rec, forKey: kvsKey)
    }

    /// The folder another device opened in the last hour, if any.
    static func lastFolderFromAnotherDevice() -> (String, String)? {
        guard let rec = NSUbiquitousKeyValueStore.default.dictionary(forKey: kvsKey),
              let s = rec["server"] as? String, let p = rec["path"] as? String, let dev = rec["device"] as? String, let at = rec["at"] as? Double else { return nil }
        guard dev != DeviceIdentity.id, Date().timeIntervalSince1970 - at < 3600, p != "/" else { return nil }
        return (s, p)
    }
}
