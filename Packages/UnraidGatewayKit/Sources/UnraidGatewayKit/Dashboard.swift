import Foundation

/// The dashboard query and its decoded shape. Every field below was validated
/// against Unraid 7.3 / unraid-api 4.37 with a VIEWER-role API key.
public struct Dashboard: Decodable, Sendable {
    public static let query = """
    { array { state capacity { kilobytes { free used total } } disks { name status temp fsSize fsFree } parityCheckStatus { status progress running } }
      shares { name free used comment }
      docker { containers { id names state image autoStart isUpdateAvailable webUiUrl iconUrl } }
      info { os { hostname uptime release } cpu { brand cores threads } }
      notifications { overview { unread { total warning alert } } }
      metrics { cpu { percentTotal } memory { percentTotal used total } } }
    """

    public struct Array: Decodable, Sendable {
        public var state: String
        public var capacity: Capacity?
        public var disks: [Disk]
        public var parityCheckStatus: Parity?
        public struct Capacity: Decodable, Sendable { public var kilobytes: KB
            public struct KB: Decodable, Sendable { public var free: String; public var used: String; public var total: String } }
        public struct Disk: Decodable, Sendable { public var name: String; public var status: String?; public var temp: Int?; public var fsSize: Int64?; public var fsFree: Int64? }
        public struct Parity: Decodable, Sendable { public var status: String?; public var progress: Int?; public var running: Bool? }
    }
    public struct Share: Decodable, Sendable { public var name: String; public var free: Int64?; public var used: Int64?; public var comment: String? }
    public struct Docker: Decodable, Sendable { public var containers: [Container] }
    public struct Container: Decodable, Sendable, Identifiable {
        public var id: String; public var names: [String]; public var state: String; public var image: String?
        public var autoStart: Bool?; public var isUpdateAvailable: Bool?; public var webUiUrl: String?; public var iconUrl: String?
        public var displayName: String { names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? id }
    }
    public struct Info: Decodable, Sendable {
        public var os: OS?; public var cpu: CPU?
        public struct OS: Decodable, Sendable { public var hostname: String?; public var uptime: String?; public var release: String? }
        public struct CPU: Decodable, Sendable { public var brand: String?; public var cores: Int?; public var threads: Int? }
    }
    public struct Notifications: Decodable, Sendable { public var overview: Overview?
        public struct Overview: Decodable, Sendable { public var unread: Counts?
            public struct Counts: Decodable, Sendable { public var total: Int?; public var warning: Int?; public var alert: Int? } } }
    public struct Metrics: Decodable, Sendable {
        public var cpu: CPU?; public var memory: Memory?
        public struct CPU: Decodable, Sendable { public var percentTotal: Double? }
        public struct Memory: Decodable, Sendable { public var percentTotal: Double?; public var used: Int64?; public var total: Int64? }
    }

    public var array: Array?
    public var shares: [Share]?
    public var docker: Docker?
    public var info: Info?
    public var notifications: Notifications?
    public var metrics: Metrics?

    /// Array capacity in bytes derived from the kilobyte strings.
    public var arrayBytes: (free: Int64, used: Int64, total: Int64)? {
        guard let kb = array?.capacity?.kilobytes, let f = Int64(kb.free), let u = Int64(kb.used), let t = Int64(kb.total) else { return nil }
        return (f * 1024, u * 1024, t * 1024)
    }
}
