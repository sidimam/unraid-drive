import Foundation

/// An in-process fake of unraid-gateway, served through a `URLProtocol`, so the
/// whole app (and the File Provider extension) can run without a server.
/// Used for App Store review and for trying the app before installing the
/// container. The sample filesystem is persisted in the app group so the app
/// and the extension see the same files.
public enum DemoGateway {
    public static let host = "demo.unraid-drive.invalid"
    public static let baseURL = URL(string: "https://\(host)")!
    public static let apiKey = "demo"

    public static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

// MARK: - Sample filesystem

final class DemoFilesystem: @unchecked Sendable {
    static let shared = DemoFilesystem()

    struct Node: Codable {
        var isDir: Bool
        var data: Data
        var mtime: Date
    }

    private let lock = NSLock()
    private var nodes: [String: Node] = [:]
    private var uploads: [String: (path: String, data: Data)] = [:]
    private let fileURL: URL?

    private init() {
        fileURL = AppGroup.containerURL?.appendingPathComponent("demo-fs.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([String: Node].self, from: data), !saved.isEmpty {
            nodes = saved
        } else {
            seed()
        }
    }

    private func seed() {
        let now = Date()
        func dir(_ p: String) { nodes[p] = Node(isDir: true, data: Data(), mtime: now.addingTimeInterval(-86400 * 3)) }
        func file(_ p: String, _ text: String, age: TimeInterval = 3600) { nodes[p] = Node(isDir: false, data: Data(text.utf8), mtime: now.addingTimeInterval(-age)) }
        dir("/documents"); dir("/documents/Invoices"); dir("/documents/Notes"); dir("/media"); dir("/media/Photos"); dir("/downloads")
        file("/documents/Welcome.md", """
        # Welcome to Unraid Drive

        This is the demo server: a sample of what your Unraid shares look like in the Files app.
        Everything here lives on this device only. Create, rename, move and delete files freely.

        To connect a real server, install the `unraid-gateway` container on Unraid and add it with your API key.
        """, age: 7200)
        file("/documents/Invoices/2026-01 Electricity.txt", "Invoice 2026-01\nAmount: 84.20 EUR\nStatus: paid\n", age: 86400 * 40)
        file("/documents/Invoices/2026-02 Internet.txt", "Invoice 2026-02\nAmount: 29.90 EUR\nStatus: paid\n", age: 86400 * 12)
        file("/documents/Notes/Shopping list.txt", "- Coffee\n- Olive oil\n- Parmigiano\n", age: 5400)
        file("/documents/Notes/Ideas.txt", "Ideas for the weekend:\n1. Bike ride\n2. Organise the photo archive on the NAS\n", age: 900)
        file("/media/Photos/README.txt", "Drop photos from the Files app here and they land on the NAS.\n", age: 86400)
        file("/downloads/linux-iso-checksums.txt", "sha256  ubuntu-26.04-live-server-amd64.iso  0000...\n", age: 86400 * 2)
        file("/downloads/sample-data.csv", "date,share,used_gb\n2026-09-01,documents,9120\n2026-09-01,media,9800\n2026-09-01,downloads,410\n", age: 600)
        persist()
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(nodes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // All accessors take the lock.
    func with<T>(_ body: (inout [String: Node]) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        let r = body(&nodes)
        persist()
        return r
    }
    func read<T>(_ body: ([String: Node]) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(nodes)
    }
    func uploadSession(_ id: String) -> (path: String, data: Data)? { lock.lock(); defer { lock.unlock() }; return uploads[id] }
    func setUploadSession(_ id: String, _ v: (path: String, data: Data)?) { lock.lock(); defer { lock.unlock() }; uploads[id] = v }
}

// MARK: - URLProtocol

final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == DemoGateway.host
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, headers, body) = Self.handle(request)
        var h = headers
        h["Content-Length"] = String(body.count)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: h)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    // MARK: routing

    private static func json(_ status: Int, _ obj: Any, headers: [String: String] = [:]) -> (Int, [String: String], Data) {
        var h = headers; h["Content-Type"] = "application/json"
        return (status, h, (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }
    private static func err(_ status: Int, _ msg: String) -> (Int, [String: String], Data) { json(status, ["error": msg]) }

    private static func entry(_ path: String, _ n: DemoFilesystem.Node) -> [String: Any] {
        [
            "name": GatewayPath.name(path), "path": path, "type": n.isDir ? "dir" : "file",
            "size": n.isDir ? 0 : n.data.count, "mtime": GatewayJSON.rfc3339.string(from: n.mtime),
            "etag": "\"\(n.data.count)-\(Int64(n.mtime.timeIntervalSince1970 * 1e9))\"", "mode": n.isDir ? "drwxrwxr-x" : "-rw-rw-r--",
        ]
    }

    private static func body(_ req: URLRequest) -> Data {
        if let b = req.httpBody { return b }
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var out = Data(); var buf = [UInt8](repeating: 0, count: 65536)
        while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; out.append(buf, count: n) }
        return out
    }

    private static func handle(_ req: URLRequest) -> (Int, [String: String], Data) {
        guard let url = req.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return err(400, "bad url") }
        let path = comps.path
        let q: (String) -> String? = { k in comps.queryItems?.first { $0.name == k }?.value }
        let method = req.httpMethod ?? "GET"
        let fs = DemoFilesystem.shared

        if path == "/healthz" { return json(200, ["status": "ok", "version": "demo"]) }
        if path == "/api/v1/auth/login" {
            let b = (try? JSONSerialization.jsonObject(with: body(req))) as? [String: Any]
            guard b?["apiKey"] as? String == DemoGateway.apiKey else { return err(401, "invalid api key") }
            return json(200, ["token": "demo-token", "expiresAt": GatewayJSON.rfc3339.string(from: Date().addingTimeInterval(43200)),
                              "identity": ["name": "demo", "roles": ["VIEWER"]], "readOnly": false, "version": "demo"])
        }
        guard req.value(forHTTPHeaderField: "Authorization") == "Bearer demo-token" || req.value(forHTTPHeaderField: "x-api-key") == DemoGateway.apiKey else {
            return err(401, "authentication required")
        }
        if path == "/api/v1/auth/logout" { return (204, [:], Data()) }
        if path == "/api/v1/auth/session" || path == "/api/v1/info" { return json(200, ["identity": ["name": "demo", "roles": ["VIEWER"]], "readOnly": false, "version": "demo"]) }
        if path == "/api/v1/graphql" { return json(200, demoDashboard) }

        let jsonBody = (try? JSONSerialization.jsonObject(with: body(req))) as? [String: Any] ?? [:]
        switch (method, path) {
        case ("GET", "/api/v1/fs/list"):
            let p = GatewayPath.clean(q("path") ?? "/")
            return fs.read { nodes in
                if p != "/" { guard let n = nodes[p] else { return err(404, "not found") }; guard n.isDir else { return err(400, "not a directory") } }
                let children = nodes.filter { GatewayPath.parent($0.key) == p && $0.key != "/" }
                    .sorted { ($0.value.isDir ? 0 : 1, $0.key.lowercased()) < ($1.value.isDir ? 0 : 1, $1.key.lowercased()) }
                    .map { entry($0.key, $0.value) }
                let mt = nodes[p]?.mtime ?? Date(timeIntervalSince1970: 0)
                return json(200, ["path": p, "etag": "\"dir-\(Int64(mt.timeIntervalSince1970))\"", "mtime": GatewayJSON.rfc3339.string(from: mt), "entries": children])
            }
        case ("GET", "/api/v1/fs/stat"):
            let p = GatewayPath.clean(q("path") ?? "/")
            return fs.read { nodes in nodes[p].map { json(200, entry(p, $0)) } ?? err(404, "not found") }
        case ("GET", "/api/v1/fs/content"), ("HEAD", "/api/v1/fs/content"):
            let p = GatewayPath.clean(q("path") ?? "/")
            return fs.read { nodes in
                guard let n = nodes[p] else { return err(404, "not found") }
                guard !n.isDir else { return err(400, "is a directory") }
                return (200, ["Content-Type": "application/octet-stream", "ETag": "\"\(n.data.count)-\(Int64(n.mtime.timeIntervalSince1970 * 1e9))\""], method == "HEAD" ? Data() : n.data)
            }
        case ("PUT", "/api/v1/fs/content"):
            let p = GatewayPath.clean(q("path") ?? "/")
            let data = body(req)
            let mt = req.value(forHTTPHeaderField: "X-Mtime").flatMap { GatewayJSON.rfc3339.date(from: $0) } ?? Date()
            return fs.with { nodes in
                guard GatewayPath.depth(p) >= 2, nodes[GatewayPath.parent(p)]?.isDir == true else { return err(404, "share not found") }
                if let n = nodes[p], n.isDir { return err(409, "target is a directory") }
                if nodes[p] != nil, q("overwrite") == "false" { return err(409, "already exists") }
                let existed = nodes[p] != nil
                nodes[p] = .init(isDir: false, data: data, mtime: mt)
                touch(&nodes, GatewayPath.parent(p))
                return json(existed ? 200 : 201, entry(p, nodes[p]!))
            }
        case ("POST", "/api/v1/fs/mkdir"):
            let p = GatewayPath.clean(jsonBody["path"] as? String ?? "")
            return fs.with { nodes in
                guard GatewayPath.depth(p) >= 2 else { return err(403, "the root only contains mounted shares; create folders inside a share") }
                guard nodes[GatewayPath.parent(p)]?.isDir == true else { return err(404, "not found") }
                guard nodes[p] == nil else { return err(409, "already exists") }
                nodes[p] = .init(isDir: true, data: Data(), mtime: Date())
                touch(&nodes, GatewayPath.parent(p))
                return json(201, entry(p, nodes[p]!))
            }
        case ("POST", "/api/v1/fs/move"), ("POST", "/api/v1/fs/copy"):
            let from = GatewayPath.clean(jsonBody["from"] as? String ?? ""), to = GatewayPath.clean(jsonBody["to"] as? String ?? "")
            let overwrite = jsonBody["overwrite"] as? Bool ?? false
            let isMove = path.hasSuffix("move")
            return fs.with { nodes in
                guard GatewayPath.depth(from) >= 2, GatewayPath.depth(to) >= 2 else { return err(403, "shares are mount points and cannot be moved, renamed or replaced") }
                guard nodes[from] != nil else { return err(404, "not found") }
                guard nodes[GatewayPath.parent(to)]?.isDir == true else { return err(404, "not found") }
                if nodes[to] != nil && !overwrite { return err(409, "destination already exists") }
                if to == from || to.hasPrefix(from + "/") { return err(400, "destination is inside source") }
                for (k, v) in nodes where k == from || k.hasPrefix(from + "/") {
                    let nk = to + k.dropFirst(from.count)
                    nodes[nk] = v
                    if isMove { nodes[k] = nil }
                }
                touch(&nodes, GatewayPath.parent(from)); touch(&nodes, GatewayPath.parent(to))
                return json(isMove ? 200 : 201, entry(to, nodes[to]!))
            }
        case ("POST", "/api/v1/fs/delete"):
            let p = GatewayPath.clean(jsonBody["path"] as? String ?? "")
            return fs.with { nodes in
                guard GatewayPath.depth(p) >= 2 else { return err(403, "shares are mount points and cannot be deleted") }
                guard nodes[p] != nil else { return err(404, "not found") }
                for k in nodes.keys where k == p || k.hasPrefix(p + "/") { nodes[k] = nil }
                touch(&nodes, GatewayPath.parent(p))
                return (204, [:], Data())
            }
        case ("GET", "/api/v1/fs/changes"):
            let p = GatewayPath.clean(q("path") ?? "/")
            let since = Int64(q("since") ?? "0") ?? 0
            let cursor = Int64(Date().timeIntervalSince1970 * 1e9) - 2_000_000_000
            return fs.read { nodes in
                var dirs: [String] = [], files: [[String: Any]] = []
                var scanned = 0
                for (k, v) in nodes where k == p || k.hasPrefix(p == "/" ? "/" : p + "/") {
                    scanned += 1
                    guard Int64(v.mtime.timeIntervalSince1970 * 1e9) > since else { continue }
                    if v.isDir { dirs.append(k) } else { files.append(entry(k, v)) }
                }
                if p == "/" && since == 0 { dirs.append("/") }
                return json(200, ["path": p, "since": since, "cursor": cursor, "dirs": dirs.sorted(), "files": files, "truncated": false, "scanned": scanned])
            }
        case ("POST", "/api/v1/fs/uploads"):
            let p = GatewayPath.clean(jsonBody["path"] as? String ?? "")
            let id = UUID().uuidString.lowercased()
            fs.setUploadSession(id, (p, Data()))
            return json(201, ["id": id, "path": p, "offset": 0, "expiresAt": GatewayJSON.rfc3339.string(from: Date().addingTimeInterval(86400))], headers: ["Upload-Offset": "0"])
        default:
            break
        }
        if path.hasPrefix("/api/v1/fs/uploads/") {
            let rest = path.dropFirst("/api/v1/fs/uploads/".count)
            let id = String(rest.split(separator: "/").first ?? "")
            guard var up = fs.uploadSession(id) else { return err(404, "upload not found or expired") }
            if rest.hasSuffix("/commit") {
                let mt = req.value(forHTTPHeaderField: "X-Mtime").flatMap { GatewayJSON.rfc3339.date(from: $0) } ?? Date()
                fs.setUploadSession(id, nil)
                return fs.with { nodes in
                    nodes[up.path] = .init(isDir: false, data: up.data, mtime: mt)
                    touch(&nodes, GatewayPath.parent(up.path))
                    return json(201, entry(up.path, nodes[up.path]!))
                }
            }
            switch method {
            case "HEAD", "GET": return json(200, ["id": id, "path": up.path, "offset": up.data.count], headers: ["Upload-Offset": String(up.data.count)])
            case "PATCH":
                guard Int(req.value(forHTTPHeaderField: "Upload-Offset") ?? "") == up.data.count else {
                    return json(409, ["error": "offset mismatch"], headers: ["Upload-Offset": String(up.data.count)])
                }
                up.data.append(body(req)); fs.setUploadSession(id, up)
                return (204, ["Upload-Offset": String(up.data.count)], Data())
            case "DELETE": fs.setUploadSession(id, nil); return (204, [:], Data())
            default: break
            }
        }
        return err(404, "not found")
    }

    private static func touch(_ nodes: inout [String: DemoFilesystem.Node], _ dir: String) {
        if var d = nodes[dir] { d.mtime = Date(); nodes[dir] = d }
    }

    /// Canned dashboard matching `Dashboard.query`.
    private static var demoDashboard: [String: Any] {
        ["data": [
            "array": ["state": "STARTED", "capacity": ["kilobytes": ["free": "8459410862", "used": "9538660024", "total": "17998070886"]],
                      "disks": [["name": "disk1", "status": "DISK_OK", "temp": 38, "fsSize": 8999035443, "fsFree": 4229705431], ["name": "disk2", "status": "DISK_OK", "temp": 41, "fsSize": 8999035443, "fsFree": 4229705431]],
                      "parityCheckStatus": ["status": "COMPLETED", "progress": 100, "running": false]],
            "shares": [["name": "documents", "free": 10193582739, "used": 9800498, "comment": "Documents and scans"],
                       ["name": "media", "free": 10193582739, "used": 6800498323, "comment": "Photos, music and video"],
                       ["name": "downloads", "free": 10193582739, "used": 410000000, "comment": ""]],
            "docker": ["containers": [
                ["id": "1", "names": ["/unraid-gateway"], "state": "RUNNING", "image": "ghcr.io/sidimam/unraid-gateway:latest", "autoStart": true, "isUpdateAvailable": false, "webUiUrl": nil, "iconUrl": nil],
                ["id": "2", "names": ["/jellyfin"], "state": "RUNNING", "image": "jellyfin/jellyfin", "autoStart": true, "isUpdateAvailable": true, "webUiUrl": nil, "iconUrl": nil],
                ["id": "3", "names": ["/paperless-ngx"], "state": "EXITED", "image": "ghcr.io/paperless-ngx/paperless-ngx", "autoStart": false, "isUpdateAvailable": false, "webUiUrl": nil, "iconUrl": nil]]],
            "info": ["os": ["hostname": "demo-nas", "uptime": GatewayJSON.rfc3339.string(from: Date().addingTimeInterval(-86400 * 12)), "release": "7.3.2"],
                     "cpu": ["brand": "Intel Core i5-12400", "cores": 6, "threads": 12]],
            "notifications": ["overview": ["unread": ["total": 2, "warning": 1, "alert": 0]]],
            "metrics": ["cpu": ["percentTotal": 7.5], "memory": ["percentTotal": 34.0, "used": 22000000000, "total": 64000000000]],
        ]]
    }
}
