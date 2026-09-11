import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import IOKit
#endif

/// Keys shared by the app, the Apple TV app and the File Provider extension for the optional
/// iCloud configuration backup (Key-Value Storage).
public enum CloudKeys {
    /// The server list (names, URLs, modes, chosen shares); secrets travel through iCloud Keychain.
    public static let servers = "servers.v1"
    /// Map "hardware fingerprint → device id": lets a reinstalled app on the same device keep its
    /// gateway registration instead of appearing as a new device.
    public static let deviceIDs = "device.ids.v1"
}

/// A stable id for this installation, shared by the app and its extensions through the app group.
/// The gateway registers it on the first sign-in; removing the device on the gateway forces a new
/// sign-in here.
///
/// A reinstall wipes the app group. To come back as the *same* device, the app stores the pair
/// "fingerprint of this hardware → id" in iCloud Key-Value Storage: on the next first launch on the
/// same hardware `adoptFromCloudIfNeeded()` finds the old id and reuses it (build 30+). When the
/// fingerprint is not recoverable the id is regenerated and the gateway marks the previous entry
/// with the same name as superseded.
public enum DeviceIdentity {
    static let key = "device.id"

    public static var id: String {
        if let v = AppGroup.defaults.string(forKey: key), !v.isEmpty { return v }
        let v = UUID().uuidString
        AppGroup.defaults.set(v, forKey: key)
        return v
    }

    /// True when an id already exists locally (i.e. this is not a fresh install).
    public static var hasLocalID: Bool {
        !(AppGroup.defaults.string(forKey: key) ?? "").isEmpty
    }

    /// A per-hardware fingerprint that survives a reinstall of this app: `identifierForVendor` on
    /// iPhone/iPad/Vision Pro/Apple TV (kept while another app of the same developer stays installed),
    /// the platform UUID on the Mac. Nil when the platform gives none.
    public static var hardwareFingerprint: String? {
        #if os(macOS)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let v = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) else { return nil }
        return (v.takeRetainedValue() as? String).map { "mac:" + $0 }
        #elseif canImport(UIKit)
        return UIDevice.current.identifierForVendor.map { "vendor:" + $0.uuidString }
        #else
        return nil
        #endif
    }

    /// Call once at app start (apps only — the Key-Value Store is not for extensions).
    /// - On a fresh install: if iCloud remembers an id for this hardware, adopt it (the gateway sees
    ///   the same device again). Otherwise a new id is created.
    /// - Always: record "fingerprint → id" in iCloud for the next reinstall.
    /// Returns true when an id was adopted from iCloud.
    @discardableResult
    public static func adoptFromCloudIfNeeded() -> Bool {
        guard let fp = hardwareFingerprint else { _ = id; return false }
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()
        var map = kvs.dictionary(forKey: CloudKeys.deviceIDs) as? [String: String] ?? [:]
        var adopted = false
        if !hasLocalID, let previous = map[fp], !previous.isEmpty {
            AppGroup.defaults.set(previous, forKey: key)
            adopted = true
        }
        let current = id
        if map[fp] != current {
            map[fp] = current
            kvs.set(map, forKey: CloudKeys.deviceIDs)
            kvs.synchronize()
        }
        return adopted
    }
}
