import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct GraphQLEnvelope<T: Decodable>: Decodable {
    var data: T?
    var errors: [GQLError]?
    struct GQLError: Decodable { var message: String }
}

/// Async client for the unraid-gateway HTTP API.
///
/// Authentication: the API key is exchanged for a session token on first use;
/// a 401 triggers exactly one transparent re-login and retry.
public actor GatewayClient {
    public let baseURL: URL
    private let apiKey: String
    private let username: String?
    private let password: String?
    private let extraHeaders: [String: String]
    private let session: URLSession
    private var token: String?
    private var loginTask: Task<String, Error>?
    /// Share permissions of the last login (nil when the session is unrestricted).
    public private(set) var sharePermissions: [String: ShareAccess]?
    public private(set) var currentUser: String?

    /// Uploads larger than this use the resumable protocol.
    public private(set) var resumableThreshold: Int64 = 16 * 1024 * 1024
    public private(set) var chunkSize: Int = 8 * 1024 * 1024
    public func setResumableThreshold(_ n: Int64) { resumableThreshold = n }
    public func setChunkSize(_ n: Int) { chunkSize = n }

    /// - Parameters:
    ///   - username/password: optional Unraid user; the gateway then applies that user's share permissions.
    ///   - extraHeaders: sent on every request, e.g. a Cloudflare Access service token.
    public init(baseURL: URL, apiKey: String, username: String? = nil, password: String? = nil, extraHeaders: [String: String] = [:], session: URLSession? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.username = (username?.isEmpty ?? true) ? nil : username
        self.password = password
        self.extraHeaders = extraHeaders
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 24 * 3600
            cfg.waitsForConnectivity = false
            cfg.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: cfg)
        }
    }

    // MARK: - Public API

    public func health() async throws -> HealthResponse {
        let (data, resp) = try await perform(URLRequest(url: url("/healthz")))
        try Self.check(resp, data)
        return try decode(HealthResponse.self, data)
    }

    /// Validates the API key and caches the session token.
    @discardableResult
    /// Signs in. `register` is set by the user's own actions (adding a server, "connect again"):
    /// it registers this installation on the gateway (0.9+). Background logins never register, so
    /// a device the admin removed stays out until the user acts.
    public func login(register: Bool = false) async throws -> LoginResponse {
        var req = URLRequest(url: url("/api/v1/auth/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["apiKey": apiKey, "deviceId": DeviceIdentity.id, "deviceName": Self.clientDescription, "registerDevice": register]
        if let username { body["username"] = username; body["password"] = password ?? "" }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await perform(req)
        if (resp as? HTTPURLResponse)?.statusCode == 401, username == nil,
           let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"], msg.contains("username") {
            throw GatewayError.userRequired
        }
        try Self.check(resp, data)
        let login = try decode(LoginResponse.self, data)
        token = login.token
        currentUser = login.user
        if let shares = login.shares {
            var perms: [String: ShareAccess] = [:]
            for (k, v) in shares { if let a = ShareAccess(v) { perms[k.lowercased()] = a } }
            sharePermissions = perms
        } else {
            sharePermissions = nil
        }
        return login
    }

    /// Access level for a share name, or nil when unknown/unrestricted (call after login).
    public func access(forShare share: String) -> ShareAccess? {
        sharePermissions?[share.lowercased()]
    }

    public func logout() async {
        guard let t = token else { return }
        var req = URLRequest(url: url("/api/v1/auth/logout"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
        token = nil
    }

    public func list(_ path: String, hidden: Bool = false) async throws -> ListResponse {
        var items = [URLQueryItem(name: "path", value: path)]
        if hidden { items.append(URLQueryItem(name: "hidden", value: "1")) }
        let (data, _) = try await authorized(get("/api/v1/fs/list", items))
        return try decode(ListResponse.self, data)
    }

    public func stat(_ path: String) async throws -> FSEntry {
        let (data, _) = try await authorized(get("/api/v1/fs/stat", [URLQueryItem(name: "path", value: path)]))
        return try decode(FSEntry.self, data)
    }

    /// Authorized GET for a file's content, for players that stream by themselves (AVPlayer on tvOS):
    /// carries the session token and the extra headers (Cloudflare Access). The gateway supports HTTP ranges.
    public func mediaRequest(_ path: String) async throws -> URLRequest {
        var req = get("/api/v1/fs/content", [URLQueryItem(name: "path", value: path)])
        req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue(Self.clientDescription, forHTTPHeaderField: Self.clientHeader)
        return req
    }

    /// A short-lived URL for one file that needs no headers (gateway 0.6+): for players that cannot
    /// send the bearer token, such as libmpv on Apple TV. Read access is checked when issuing it.
    public func mediaTicketURL(_ path: String, ttl: String = "8h") async throws -> URL {
        struct Ticket: Decodable { var url: String; var expiresAt: Date }
        let (data, _) = try await authorized(post("/api/v1/fs/ticket", ["path": path, "ttl": ttl]))
        let t = try decode(Ticket.self, data)
        guard let url = URL(string: t.url, relativeTo: baseURL)?.absoluteURL else { throw GatewayError.decoding("ticket url") }
        return url
    }

    /// Checks that a media request really returns the file before handing it to a player: mpv only
    /// says "unrecognized file format" when it receives a login page, a JSON error or a proxy page.
    /// Sends the same headers as the app and asks for the first byte only. Returns nil when the
    /// response is a file, otherwise a message that says what answered instead.
    public func mediaPreflight(_ request: URLRequest) async -> String? {
        var req = request
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return String(localized: "The gateway did not answer.", bundle: .module) }
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.contains("text/html") {
                return String(localized: "A web page answered instead of the file (\(http.url?.host ?? "proxy")): usually a Cloudflare Access login. Check the service token in the server's settings.", bundle: .module)
            }
            if http.statusCode >= 400 {
                let payload = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
                let msg = payload["error"] ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                switch payload["code"] {
                case "device_revoked": return GatewayError.deviceRevoked.errorDescription
                case "device_not_registered": return GatewayError.deviceNotRegistered.errorDescription
                default: break
                }
                if http.statusCode == 401 { return GatewayError.unauthorized.errorDescription }
                return String(localized: "The gateway answered \(http.statusCode): \(msg)", bundle: .module)
            }
            if type.contains("application/json") {
                return String(localized: "The gateway answered with JSON instead of the file: update unraid-gateway.", bundle: .module)
            }
            return nil
        } catch {
            return GatewayError.network(error.localizedDescription).errorDescription
        }
    }

    /// Downloads a file to a temporary location owned by the caller.
    public func download(_ path: String, to destination: URL) async throws -> FSEntry {
        let req = get("/api/v1/fs/content", [URLQueryItem(name: "path", value: path)])
        let (tmp, resp) = try await authorizedDownload(req)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
        // Build the entry from headers to avoid a second round trip.
        let http = resp as? HTTPURLResponse
        let etag = http?.value(forHTTPHeaderField: "ETag") ?? ""
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        let mtime = http?.value(forHTTPHeaderField: "Last-Modified").flatMap(Self.httpDate) ?? Date()
        return FSEntry(name: GatewayPath.name(path), path: path, type: .file, size: size, mtime: mtime, etag: etag)
    }

    /// Uploads a local file to `path`. Small files use one atomic PUT; large
    /// files use the resumable session protocol and survive offset mismatches.
    public func upload(fileURL: URL, to path: String, overwrite: Bool = true, mtime: Date? = nil, ifMatch: String? = nil,
                       progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> FSEntry {
        let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        if size <= resumableThreshold {
            var items = [URLQueryItem(name: "path", value: path)]
            if !overwrite { items.append(URLQueryItem(name: "overwrite", value: "false")) }
            var req = get("/api/v1/fs/content", items)
            req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            if let mtime { req.setValue(GatewayJSON.rfc3339.string(from: mtime), forHTTPHeaderField: "X-Mtime") }
            if let ifMatch { req.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
            let (data, _) = try await authorizedUpload(req, fromFile: fileURL)
            progress?(size, size)
            return try decode(FSEntry.self, data)
        }
        return try await resumableUpload(fileURL: fileURL, size: size, to: path, overwrite: overwrite, mtime: mtime, progress: progress)
    }

    public func mkdir(_ path: String, parents: Bool = false) async throws -> FSEntry {
        let (data, _) = try await authorized(post("/api/v1/fs/mkdir", ["path": path, "parents": parents]))
        return try decode(FSEntry.self, data)
    }

    public func move(_ from: String, to: String, overwrite: Bool = false) async throws -> FSEntry {
        let (data, _) = try await authorized(post("/api/v1/fs/move", ["from": from, "to": to, "overwrite": overwrite]))
        return try decode(FSEntry.self, data)
    }

    public func copy(_ from: String, to: String, overwrite: Bool = false) async throws -> FSEntry {
        let (data, _) = try await authorized(post("/api/v1/fs/copy", ["from": from, "to": to, "overwrite": overwrite]))
        return try decode(FSEntry.self, data)
    }

    public func delete(_ path: String, recursive: Bool = true) async throws {
        _ = try await authorized(post("/api/v1/fs/delete", ["path": path, "recursive": recursive]))
    }

    /// One page of the change feed. Pass `after`/`cursor` from a truncated page to continue.
    public func changes(_ path: String, since: Int64, after: String? = nil, cursor: Int64? = nil, limit: Int? = nil) async throws -> ChangesPage {
        var items = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "since", value: String(since))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        let (data, _) = try await authorized(get("/api/v1/fs/changes", items))
        return try decode(ChangesPage.self, data)
    }

    /// Id-based change journal (gateway 0.5+). `seq` 0 = first sync.
    public func journal(seq: Int64, limit: Int? = nil) async throws -> JournalPage {
        var items = [URLQueryItem(name: "path", value: "/"), URLQueryItem(name: "seq", value: String(seq))]
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        let (data, _) = try await authorized(get("/api/v1/fs/changes", items))
        return try decode(JournalPage.self, data)
    }

    /// Resolves a server item id to its current entry (gateway 0.5+).
    public func item(id: String) async throws -> FSEntry {
        let (data, _) = try await authorized(get("/api/v1/fs/item", [URLQueryItem(name: "id", value: id)]))
        return try decode(FSEntry.self, data)
    }

    /// Runs a GraphQL query through the gateway proxy and returns the `data` object.
    public func graphQL<T: Decodable>(_ query: String, variables: [String: Any]? = nil, as type: T.Type) async throws -> T {
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        let (data, _) = try await authorized(post("/api/v1/graphql", body))
        let env = try decode(GraphQLEnvelope<T>.self, data)
        if let errs = env.errors, !errs.isEmpty, env.data == nil {
            throw GatewayError.graphQL(errs.map(\.message))
        }
        guard let d = env.data else { throw GatewayError.decoding("empty GraphQL data") }
        return d
    }

    /// Raw GraphQL passthrough for ad-hoc queries.
    public func graphQLRaw(_ query: String) async throws -> Data {
        let (data, _) = try await authorized(post("/api/v1/graphql", ["query": query]))
        return data
    }

    // MARK: - Resumable upload

    private func resumableUpload(fileURL: URL, size: Int64, to path: String, overwrite: Bool, mtime: Date?,
                                 progress: (@Sendable (Int64, Int64) -> Void)?) async throws -> FSEntry {
        let (data, _) = try await authorized(post("/api/v1/fs/uploads", ["path": path, "size": size, "overwrite": overwrite]))
        let sess = try decode(UploadSession.self, data)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var offset: Int64 = sess.offset
        var attempts = 0
        while offset < size {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let chunk = handle.readData(ofLength: Int(min(Int64(chunkSize), size - offset)))
            var req = URLRequest(url: url("/api/v1/fs/uploads/\(sess.id)"))
            req.httpMethod = "PATCH"
            req.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            req.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            do {
                let (_, resp) = try await authorizedUpload(req, data: chunk)
                if let o = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Upload-Offset"), let n = Int64(o) {
                    offset = n
                } else {
                    offset += Int64(chunk.count)
                }
                attempts = 0
            } catch GatewayError.conflict {
                // Offset mismatch: ask the server where it is and continue from there.
                attempts += 1
                if attempts > 5 { throw GatewayError.conflict("upload offset mismatch") }
                var head = URLRequest(url: url("/api/v1/fs/uploads/\(sess.id)"))
                head.httpMethod = "HEAD"
                let (_, resp) = try await authorized(head)
                guard let o = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Upload-Offset"), let n = Int64(o) else {
                    throw GatewayError.conflict("upload offset unknown")
                }
                offset = n
            }
            progress?(offset, size)
        }
        var commit = URLRequest(url: url("/api/v1/fs/uploads/\(sess.id)/commit"))
        commit.httpMethod = "POST"
        if let mtime { commit.setValue(GatewayJSON.rfc3339.string(from: mtime), forHTTPHeaderField: "X-Mtime") }
        let (out, _) = try await authorized(commit)
        return try decode(FSEntry.self, out)
    }

    // MARK: - Plumbing

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func get(_ path: String, _ items: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents(url: url(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        return URLRequest(url: comps.url!)
    }

    private func post(_ path: String, _ body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func ensureToken() async throws -> String {
        if let token { return token }
        if let loginTask { return try await loginTask.value }
        let t = Task<String, Error> { try await self.login().token }
        loginTask = t
        defer { loginTask = nil }
        return try await t.value
    }

    private func authorized(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await perform(req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            token = nil
            req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
            let (d2, r2) = try await perform(req)
            try Self.check(r2, d2)
            return (d2, r2)
        }
        try Self.check(resp, data)
        return (data, resp)
    }

    private func authorizedUpload(_ request: URLRequest, fromFile file: URL? = nil, data body: Data? = nil) async throws -> (Data, URLResponse) {
        var req = request
        req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
        func send(_ r: URLRequest) async throws -> (Data, URLResponse) {
            do {
                if let file { return try await session.upload(for: decorate(r), fromFile: file) }
                return try await session.upload(for: decorate(r), from: body ?? Data())
            } catch { throw GatewayError.network(error.localizedDescription) }
        }
        var (data, resp) = try await send(req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            token = nil
            req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
            (data, resp) = try await send(req)
        }
        try Self.check(resp, data)
        return (data, resp)
    }

    private func authorizedDownload(_ request: URLRequest) async throws -> (URL, URLResponse) {
        var req = request
        req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
        func send(_ r: URLRequest) async throws -> (URL, URLResponse) {
            do { return try await session.download(for: decorate(r)) } catch { throw GatewayError.network(error.localizedDescription) }
        }
        var (tmp, resp) = try await send(req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            token = nil
            req.setValue("Bearer \(try await ensureToken())", forHTTPHeaderField: "Authorization")
            (tmp, resp) = try await send(req)
        }
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            let body = (try? Data(contentsOf: tmp)) ?? Data()
            try? FileManager.default.removeItem(at: tmp)
            try Self.check(resp, body)
        }
        return (tmp, resp)
    }

    private func perform(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: decorate(req)) } catch { throw GatewayError.network(error.localizedDescription) }
    }

    private func decorate(_ req: URLRequest) -> URLRequest {
        var r = req
        for (k, v) in extraHeaders { r.setValue(v, forHTTPHeaderField: k) }
        r.setValue(Self.clientDescription, forHTTPHeaderField: Self.clientHeader)
        r.setValue(DeviceIdentity.id, forHTTPHeaderField: "X-Unraid-Drive-Device")
        return r
    }

    /// Header that tells the gateway which device and app component is calling; shown in the
    /// gateway's Activity panel. Free text, no identifiers beyond model and OS version.
    public static let clientHeader = "X-Unraid-Drive-Client"
    /// "App", "File Provider", "Apple TV"…: set once by each process.
    nonisolated(unsafe) public static var component = "App"
    public static var clientDescription: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "Unraid Drive \(version) (\(build)) · \(deviceDescription) · \(component)"
    }
    private static var deviceDescription: String {
        #if os(macOS)
        let host = Host.current().localizedName ?? "Mac"
        return "\(host) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))"
        #elseif os(tvOS)
        // tvOS gives the name the user assigned to the Apple TV (no entitlement needed there).
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespaces)
        let tv = name.isEmpty || name.lowercased() == "apple tv" ? "Apple TV" : name
        return "\(tv) · tvOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
        #elseif os(visionOS)
        return "Apple Vision Pro · visionOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
        #else
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(Self.marketingName(model)) · iOS \(v.majorVersion).\(v.minorVersion)"
        #endif
    }
    /// Turns "iPhone17,1" into a readable family; exact marketing names change every year, so keep it generic.
    private static func marketingName(_ id: String) -> String {
        if id.hasPrefix("iPad") { return "iPad" }
        if id.hasPrefix("iPhone") { return "iPhone" }
        if id.hasPrefix("Mac") || id == "x86_64" || id == "arm64" { return "iPad app on Mac" }
        return id
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try GatewayJSON.decoder.decode(type, from: data) } catch { throw GatewayError.decoding(String(describing: error)) }
    }

    static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw GatewayError.network("no HTTP response") }
        // A JSON API never answers with HTML. If it does, a login portal (Cloudflare Access) or a
        // proxy error page intercepted the request, possibly after a redirect to another host.
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let firstByte = data.first(where: { $0 != 0x20 && $0 != 0x0a && $0 != 0x0d && $0 != 0x09 })
        if contentType.contains("text/html") || (http.statusCode < 300 && firstByte == UInt8(ascii: "<")) {
            throw GatewayError.interceptedByProxy(http.url?.host ?? "unknown host")
        }
        guard http.statusCode >= 300 else { return }
        let payload = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        let msg = payload["error"] ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        switch payload["code"] {
        case "device_revoked": throw GatewayError.deviceRevoked
        case "device_not_registered": throw GatewayError.deviceNotRegistered
        default: break
        }
        switch http.statusCode {
        case 401: throw GatewayError.unauthorized
        case 403: throw GatewayError.forbidden(msg)
        case 404: throw GatewayError.notFound
        case 409: throw GatewayError.conflict(msg)
        case 412: throw GatewayError.preconditionFailed
        case 429: throw GatewayError.locked
        default: throw GatewayError.http(http.statusCode, msg)
        }
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; return f
    }()
    private static func httpDate(_ s: String) -> Date? { httpDateFormatter.date(from: s) }
}
