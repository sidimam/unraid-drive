import Foundation

/// A file or directory as returned by the gateway file API.
public struct FSEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, dir }

    public var name: String
    public var path: String
    public var type: Kind
    public var size: Int64
    public var mtime: Date
    public var etag: String
    public var mode: String?
    /// Stable server-side identifiers (gateway 0.5+). Nil with older gateways.
    public var itemID: String?
    public var parentID: String?

    public var id: String { path }
    public var isDirectory: Bool { type == .dir }

    enum CodingKeys: String, CodingKey { case name, path, type, size, mtime, etag, mode, itemID = "id", parentID = "parentId" }

    public init(name: String, path: String, type: Kind, size: Int64, mtime: Date, etag: String, mode: String? = nil, itemID: String? = nil, parentID: String? = nil) {
        self.name = name; self.path = path; self.type = type; self.size = size; self.mtime = mtime; self.etag = etag; self.mode = mode
            self.itemID = itemID; self.parentID = parentID
    }
}

public struct ListResponse: Codable, Sendable {
    public var path: String
    public var etag: String
    public var mtime: Date
    public var entries: [FSEntry]
}

/// The id of the data root in gateway 0.5+ journals.
public let gatewayRootID = "root"

/// One entry of the id-based change journal (gateway 0.5+): `/fs/changes?seq=`.
public struct JournalChange: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case upsert, delete, move }
    public var seq: Int64
    public var kind: Kind
    public var id: String
    public var path: String
    public var oldPath: String?
    public var entry: FSEntry?
}

/// A page of the journal. `reset` means: forget everything, enumerate again and continue from `seq`.
public struct JournalPage: Codable, Sendable {
    public var seq: Int64
    public var reset: Bool
    public var changes: [JournalChange]
    public var truncated: Bool
}

/// One page of the legacy (mtime walk) change feed. See the gateway README, "Change feed".
public struct ChangesPage: Codable, Sendable {
    public var path: String
    public var since: Int64
    public var cursor: Int64
    public var dirs: [String]
    public var files: [FSEntry]
    public var truncated: Bool
    public var next: String?
    public var scanned: Int
}

public struct UploadSession: Codable, Sendable {
    public var id: String
    public var path: String
    public var offset: Int64
    public var size: Int64?
    public var expiresAt: Date
}

public struct Identity: Codable, Hashable, Sendable {
    public var name: String?
    public var roles: [String]?
}

public struct LoginResponse: Codable, Sendable {
    public var token: String
    public var expiresAt: Date
    public var identity: Identity
    public var readOnly: Bool
    public var version: String?
    /// "off" | "optional" | "required" (gateway ≥ 0.3).
    public var userAuth: String?
    /// Unraid user of the session, when the login carried credentials.
    public var user: String?
    /// Share name → "rw" | "ro" for that user (only shares the user may see).
    public var shares: [String: String]?
}

/// Per-share access as reported by the gateway for the logged-in user.
public enum ShareAccess: Sendable, Equatable {
    case readWrite, readOnly
    public init?(_ s: String) {
        switch s { case "rw": self = .readWrite; case "ro": self = .readOnly; default: return nil }
    }
}

public struct HealthResponse: Codable, Sendable {
    public var status: String
    public var version: String?
}

public enum GatewayError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case userRequired
    case locked
    case notFound
    case conflict(String)
    case preconditionFailed
    case forbidden(String)
    case http(Int, String)
    case network(String)
    case decoding(String)
    case graphQL([String])
    /// The response was a web page, not JSON: a login portal (Cloudflare Access) or a proxy error page.
    case interceptedByProxy(String)
    /// The gateway removed this installation from its device list: only a new sign-in registers it again.
    case deviceRevoked
    /// This installation is not registered on the gateway and the login did not ask to register it.
    case deviceNotRegistered

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "The server URL is not valid.", bundle: .module)
        case .unauthorized: return String(localized: "The API key, or the Unraid username and password, were rejected.", bundle: .module)
        case .userRequired: return String(localized: "This gateway requires an Unraid username and password in addition to the API key.", bundle: .module)
        case .locked: return String(localized: "Too many failed attempts. Try again in a few minutes.", bundle: .module)
        case .notFound: return String(localized: "Not found.", bundle: .module)
        case .conflict(let m): return m
        case .preconditionFailed: return String(localized: "The file changed on the server.", bundle: .module)
        case .forbidden(let m): return m
        case .http(let code, let m): return String(localized: "Server error \(code): \(m)", bundle: .module)
        case .network(let m): return String(localized: "Cannot reach the gateway: \(m)", bundle: .module)
        case .decoding(let m): return String(localized: "Unexpected response: \(m)", bundle: .module)
        case .graphQL(let msgs): return msgs.joined(separator: "\n")
        case .deviceRevoked: return String(localized: "This device was removed from the gateway. Open the server, choose Edit server or credentials and connect again to register it.", bundle: .module)
        case .deviceNotRegistered: return String(localized: "This device is not registered on the gateway. Open the server, choose Edit server or credentials and connect again to register it.", bundle: .module)
        case .interceptedByProxy(let host):
            if host.hasSuffix("cloudflareaccess.com") {
                return String(localized: "Cloudflare Access is blocking the request. Add this server with Connection: Cloudflare Access and a valid service token, and make sure the Access policy uses the Service Auth action.", bundle: .module)
            }
            return String(localized: "The server answered with a web page instead of data (\(host)). A login portal or proxy is intercepting the request: check the gateway URL and the connection mode.", bundle: .module)
        }
    }

    public var isAuthFailure: Bool {
        switch self {
        case .unauthorized, .deviceRevoked, .deviceNotRegistered: return true
        default: return false
        }
    }
}

/// Client-side path helpers. Gateway paths are always absolute, "/" separated.
public enum GatewayPath {
    public static func clean(_ p: String) -> String {
        var parts: [String] = []
        for seg in p.split(separator: "/", omittingEmptySubsequences: true) {
            if seg == "." { continue }
            if seg == ".." { _ = parts.popLast(); continue }
            parts.append(String(seg))
        }
        return "/" + parts.joined(separator: "/")
    }
    public static func parent(_ p: String) -> String {
        let c = clean(p)
        guard c != "/" else { return "/" }
        guard let i = c.lastIndex(of: "/") else { return "/" }
        return i == c.startIndex ? "/" : String(c[..<i])
    }
    public static func name(_ p: String) -> String {
        let c = clean(p)
        guard c != "/" else { return "" }
        return String(c.split(separator: "/").last ?? "")
    }
    public static func join(_ dir: String, _ name: String) -> String {
        clean(dir) == "/" ? "/" + name : clean(dir) + "/" + name
    }
    /// Depth of a path: "/" is 0, "/share" is 1, "/share/x" is 2.
    public static func depth(_ p: String) -> Int {
        clean(p).split(separator: "/").count
    }
}

/// JSON coding shared by the client: RFC 3339 dates with optional fractions.
public enum GatewayJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let t = frac.date(from: s) ?? plain.date(from: s) { return t }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    public static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}
