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
    /// Set while the local id was minted here and never confirmed by a gateway registration: such
    /// an id may still be replaced by the one iCloud remembers for this hardware.
    static let provisionalKey = "device.id.provisional"

    public static var id: String {
        if let v = AppGroup.defaults.string(forKey: key), !v.isEmpty { return v }
        let v = UUID().uuidString
        AppGroup.defaults.set(v, forKey: key)
        AppGroup.defaults.set(true, forKey: provisionalKey)
        Diag.info("device", "new installation id \(v.prefix(8)) (provisional until the first registration)")
        return v
    }

    /// True when an id already exists locally (i.e. this is not a fresh install).
    public static var hasLocalID: Bool {
        !(AppGroup.defaults.string(forKey: key) ?? "").isEmpty
    }

    /// True until a gateway accepted a `registerDevice` sign-in with the current id.
    public static var isProvisional: Bool { AppGroup.defaults.bool(forKey: provisionalKey) }

    /// The gateway registered the current id: keep it for good and remember it in iCloud for this
    /// hardware (apps only; the extension never touches the Key-Value Store).
    public static func markRegistered(recordInCloud: Bool) {
        if isProvisional { Diag.info("device", "id \(id.prefix(8)) registered on a gateway") }
        AppGroup.defaults.set(false, forKey: provisionalKey)
        if recordInCloud { recordInCloudMap() }
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
        guard let fp = hardwareFingerprint else {
            Diag.warning("device", "no hardware fingerprint on this platform: id \(id.prefix(8)) cannot be recovered through iCloud")
            return false
        }
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()
        let map = kvs.dictionary(forKey: CloudKeys.deviceIDs) as? [String: String] ?? [:]
        let remembered = map[fp].flatMap { $0.isEmpty ? nil : $0 }
        var adopted = false
        if let remembered, remembered != AppGroup.defaults.string(forKey: key) {
            // Adopt iCloud's id when this install has none yet, or only a provisional one that no
            // gateway ever registered. A registered local id always wins.
            if !hasLocalID || isProvisional {
                AppGroup.defaults.set(remembered, forKey: key)
                AppGroup.defaults.set(false, forKey: provisionalKey)
                adopted = true
                Diag.info("device", "adopted id \(remembered.prefix(8)) remembered in iCloud for this hardware")
            }
        }
        _ = id
        // Only a confirmed (registered) id is recorded, so a fresh install whose Key-Value Store has
        // not downloaded yet cannot overwrite the id the previous installation left there — until
        // build 36 that overwrite happened on every reinstall done before iCloud had synced.
        if !isProvisional { recordInCloudMap() }
        else if remembered == nil { Diag.info("device", "iCloud has no id for this hardware yet; will adopt one if it arrives before the first registration") }
        return adopted
    }

    /// Called again when the Key-Value Store reports an external change: a fresh install that is
    /// still provisional adopts the id iCloud remembers for this hardware.
    @discardableResult
    public static func reconcileWithCloud() -> Bool {
        guard isProvisional else { return false }
        return adoptFromCloudIfNeeded()
    }

    /// Writes "fingerprint → id" to iCloud when it differs from what is stored there.
    static func recordInCloudMap() {
        guard let fp = hardwareFingerprint else { return }
        let kvs = NSUbiquitousKeyValueStore.default
        var map = kvs.dictionary(forKey: CloudKeys.deviceIDs) as? [String: String] ?? [:]
        let current = id
        guard map[fp] != current else { return }
        map[fp] = current
        kvs.set(map, forKey: CloudKeys.deviceIDs)
        kvs.synchronize()
        Diag.info("device", "id \(current.prefix(8)) recorded in iCloud for this hardware")
    }
}
