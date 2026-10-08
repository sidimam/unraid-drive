import Foundation

/// One-glance health of a server (build 42): the dot at the top of the dashboard, next to the
/// explorer title, in the Mac menu bar panel and on Apple TV. Derived from the dashboard query
/// plus whether the gateway answered at all; every reason is kept so the UI can list them.
public struct ServerHealth: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case unknown = 0, ok, warning, error
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public var level: Level
    public var reasons: [String]
    public var date: Date

    public init(level: Level, reasons: [String] = [], date: Date = Date()) { self.level = level; self.reasons = reasons; self.date = date }

    public static let unknown = ServerHealth(level: .unknown)

    /// Gateway unreachable, authentication failed, Cloudflare Access refused: red.
    public static func unreachable(_ description: String) -> ServerHealth {
        ServerHealth(level: .error, reasons: [description])
    }

    /// Red: array not started, a disk that is not OK, a disk above the critical
    /// temperature. Yellow: a parity check with errors, CPU or memory above 90 %, a
    /// disk above the warning temperature, the gateway container not running. Green otherwise.
    public static func assess(_ d: Dashboard, gatewayContainerRunning: Bool? = nil, warnTemp: Int = 50, criticalTemp: Int = 60) -> ServerHealth {
        var errors: [String] = []; var warnings: [String] = []
        if let a = d.array {
            if a.state != "STARTED" { errors.append(String(localized: "Array \(a.state.lowercased())", bundle: .module)) }
            for disk in a.disks {
                if let s = disk.status, s != "DISK_OK", s != "DISK_NP", s != "DISK_NP_DSBL" { errors.append(String(localized: "\(disk.name): \(s)", bundle: .module)) }
                if let t = disk.temp {
                    if t >= criticalTemp { errors.append(String(localized: "\(disk.name) at \(t) °C", bundle: .module)) }
                    else if t >= warnTemp { warnings.append(String(localized: "\(disk.name) at \(t) °C", bundle: .module)) }
                }
            }
            if let p = a.parityCheckStatus, let s = p.status?.uppercased(), s.contains("ERROR") || s.contains("FAIL") { warnings.append(String(localized: "Parity check: \(s.lowercased())", bundle: .module)) }
        }
        // Unraid's own notifications are the NAS's business, not the app's (user, 8/10/2026).
        if let p = d.metrics?.cpu?.percentTotal, p > 90 { warnings.append(String(localized: "CPU load \(Int(p.rounded()))", bundle: .module) + " %") }
        if let p = d.metrics?.memory?.percentTotal, p > 90 { warnings.append(String(localized: "Memory load \(Int(p.rounded()))", bundle: .module) + " %") }
        if gatewayContainerRunning == false { warnings.append(String(localized: "unraid-gateway container not running", bundle: .module)) }
        if !errors.isEmpty { return ServerHealth(level: .error, reasons: errors + warnings) }
        if !warnings.isEmpty { return ServerHealth(level: .warning, reasons: warnings) }
        return ServerHealth(level: .ok, reasons: [])
    }
}
