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

    public var id: String { path }
    public var isDirectory: Bool { type == .dir }

    public init(name: String, path: String, type: Kind, size: Int64, mtime: Date, etag: String, mode: String? = nil) {
        self.name = name; self.path = path; self.type = type; self.size = size; self.mtime = mtime; self.etag = etag; self.mode = mode
    }
}

public struct ListResponse: Codable, Sendable {
    public var path: String
    public var etag: String
    public var mtime: Date
    public var entries: [FSEntry]
}

/// One page of the change feed. See the gateway README, "Change feed".
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

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server URL is not valid."
        case .unauthorized: return "The API key, or the Unraid username and password, were rejected."
        case .userRequired: return "This gateway requires an Unraid username and password in addition to the API key."
        case .locked: return "Too many failed attempts. Try again in a few minutes."
        case .notFound: return "Not found."
        case .conflict(let m): return m
        case .preconditionFailed: return "The file changed on the server."
        case .forbidden(let m): return m
        case .http(let code, let m): return "Server error \(code): \(m)"
        case .network(let m): return "Cannot reach the gateway: \(m)"
        case .decoding(let m): return "Unexpected response: \(m)"
        case .graphQL(let msgs): return msgs.joined(separator: "\n")
        case .interceptedByProxy(let host):
            if host.hasSuffix("cloudflareaccess.com") {
                return "Cloudflare Access is blocking the request. Add this server with Connection: Cloudflare Access and a valid service token, and make sure the Access policy uses the Service Auth action."
            }
            return "The server answered with a web page instead of data (\(host)). A login portal or proxy is intercepting the request: check the gateway URL and the connection mode."
        }
    }

    public var isAuthFailure: Bool {
        if case .unauthorized = self { return true }
        return false
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
