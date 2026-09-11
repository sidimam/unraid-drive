import Foundation

/// A stable id for this installation, shared by the app and its extensions through the app group.
/// The gateway registers it on the first sign-in; removing the device on the gateway forces a new
/// sign-in here. Regenerated only when the app group data is wiped (uninstall).
public enum DeviceIdentity {
    static let key = "device.id"
    public static var id: String {
        if let v = AppGroup.defaults.string(forKey: key), !v.isEmpty { return v }
        let v = UUID().uuidString
        AppGroup.defaults.set(v, forKey: key)
        return v
    }
}
