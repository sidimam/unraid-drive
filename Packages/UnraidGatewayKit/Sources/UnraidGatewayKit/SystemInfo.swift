import Foundation

/// "System information" sheet of the dashboard (build 42): everything the Unraid API exposes about
/// the machine. Separate from `Dashboard.query` so an unsupported field here can never break the
/// dashboard itself. Validated against Unraid 7.3.2 / unraid-api 4.37.5 with a VIEWER key.
public struct SystemInfo: Decodable, Sendable {
    public static let query = """
    { info { os { hostname fqdn distro release kernel arch uptime uefi }
             cpu { manufacturer brand cores threads processors speed speedmax socket }
             memory { layout { size type clockSpeed manufacturer } }
             baseboard { manufacturer model version memMax memSlots }
             system { manufacturer model version virtual }
             versions { core { unraid kernel api } }
             devices { gpu { id type vendorname productid class } }
             networkInterfaces { name macAddress mtu speed operstate type ipAddress } }
      metrics { memory { used total } } }
    """

    public struct Info: Decodable, Sendable {
        public var os: OS?; public var cpu: CPU?; public var memory: Memory?; public var baseboard: Baseboard?
        public var system: System?; public var versions: Versions?; public var devices: Devices?
        public var networkInterfaces: [NetworkInterface]?
        public struct OS: Decodable, Sendable { public var hostname: String?; public var fqdn: String?; public var distro: String?; public var release: String?; public var kernel: String?; public var arch: String?; public var uptime: String?; public var uefi: Bool? }
        public struct CPU: Decodable, Sendable { public var manufacturer: String?; public var brand: String?; public var cores: Int?; public var threads: Int?; public var processors: Int?; public var speed: Double?; public var speedmax: Double?; public var socket: String? }
        public struct Memory: Decodable, Sendable { public var layout: [Module]?
            public struct Module: Decodable, Sendable { public var size: Int64?; public var type: String?; public var clockSpeed: Int?; public var manufacturer: String?
                /// Module size in bytes (the API value is KiB).
                public var bytes: Int64? { size.map { $0 * 1024 } } } }
        public struct Baseboard: Decodable, Sendable { public var manufacturer: String?; public var model: String?; public var version: String?; public var memMax: Double?; public var memSlots: Double? }
        public struct System: Decodable, Sendable { public var manufacturer: String?; public var model: String?; public var version: String?; public var virtual: Bool? }
        public struct Versions: Decodable, Sendable { public var core: Core?
            public struct Core: Decodable, Sendable { public var unraid: String?; public var kernel: String?; public var api: String? } }
        public struct Devices: Decodable, Sendable { public var gpu: [GPU]?
            public struct GPU: Decodable, Sendable, Identifiable { public var id: String; public var type: String?; public var vendorname: String?; public var productid: String?; public var `class`: String? } }
        public struct NetworkInterface: Decodable, Sendable, Identifiable {
            public var id: String { name + (macAddress ?? "") }
            public var name: String; public var macAddress: String?; public var mtu: Int?; public var speed: Int?; public var operstate: String?; public var type: String?; public var ipAddress: String?
            /// Interfaces worth showing: up, with an address, not loopback/docker/veth plumbing.
            public var isRelevant: Bool {
                guard let ip = ipAddress, !ip.isEmpty, name != "lo" else { return false }
                return !name.hasPrefix("veth") && !name.hasPrefix("docker") && !name.hasPrefix("virbr")
            }
        }
    }
    public struct Metrics: Decodable, Sendable { public var memory: Memory?
        public struct Memory: Decodable, Sendable { public var used: Int64?; public var total: Int64? } }

    public var info: Info?
    public var metrics: Metrics?

    /// Boot time parsed from `os.uptime` (an ISO-8601 instant on unraid-api 4.x).
    public var bootDate: Date? {
        guard let s = info?.os?.uptime else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    /// Installed memory from the DIMM layout, in bytes (unraid-api reports module sizes in KiB).
    public var installedMemory: Int64? {
        guard let l = info?.memory?.layout, !l.isEmpty else { return nil }
        return l.compactMap(\.size).reduce(0, +) * 1024
    }
}
