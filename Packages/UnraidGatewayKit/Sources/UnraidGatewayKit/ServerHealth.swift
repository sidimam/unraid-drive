import Foundation

/// One-glance health of a server as **Unraid Drive and unraid-gateway** see it (rule of 13/10/2026):
/// the dot is about the gateway, the credentials, the Files/Finder location, the transfers and the
/// device — never about Unraid's own state (array, disks, load, notifications), which stays in the
/// dashboard as information. Every issue carries its source and, when there is one, the action
/// that fixes it, so the UI can list them ("explorable").
public struct ServerHealth: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case unknown = 0, ok, warning, error
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public enum Source: String, Sendable { case gateway, credentials, location, transfers, device, shares }
    public enum Action: String, Sendable { case none, openSystemSettings, checkLocation, signIn, openDiagnostics, retryTransfers, reRegister }
    public struct Issue: Equatable, Sendable, Identifiable {
        public var id: String { source.rawValue + "|" + detail }
        public var level: Level
        public var source: Source
        public var detail: String
        public var action: Action
        public init(_ level: Level, _ source: Source, _ detail: String, action: Action = .none) { self.level = level; self.source = source; self.detail = detail; self.action = action }
    }

    public var level: Level
    public var issues: [Issue]
    public var date: Date
    /// Plain-text reasons (every issue's detail), for compact rows and tooltips.
    public var reasons: [String] { issues.map(\.detail) }

    public init(level: Level, issues: [Issue] = [], date: Date = Date()) { self.level = level; self.issues = issues; self.date = date }
    public static let unknown = ServerHealth(level: .unknown)
    public static let fine = ServerHealth(level: .ok)

    /// Gateway unreachable, authentication failed, Cloudflare Access refused: red.
    public static func unreachable(_ description: String) -> ServerHealth {
        ServerHealth(level: .error, issues: [Issue(.error, .gateway, description, action: .signIn)])
    }

    /// Builds the summary from the collected issues: red if any error, yellow if any warning.
    public static func from(_ issues: [Issue]) -> ServerHealth {
        let worst = issues.map(\.level).max() ?? .ok
        return ServerHealth(level: worst == .unknown ? .ok : worst, issues: issues.sorted { $0.level > $1.level })
    }
}

/// `GET /api/v1/health` of unraid-gateway 0.12+: the gateway's own checks (shares mounted and
/// writable, /config, user-auth prerequisites, notification channels, devices, gateway container,
/// Unraid API reachability). Only its warnings and errors become issues in the app.
public struct GatewayHealth: Decodable, Sendable {
    public struct Check: Decodable, Sendable { public var name: String; public var level: String; public var detail: String? }
    public var status: String
    public var version: String?
    public var level: String
    public var reasons: [String]
    public var checks: [Check]

    public var issues: [ServerHealth.Issue] {
        checks.compactMap { c in
            guard let detail = c.detail, !detail.isEmpty else { return nil }
            switch c.level {
            case "error": return ServerHealth.Issue(.error, c.name.hasPrefix("shares") ? .shares : .gateway, detail)
            case "warning": return ServerHealth.Issue(.warning, c.name.hasPrefix("shares") ? .shares : .gateway, detail)
            default: return nil
            }
        }
    }
}
