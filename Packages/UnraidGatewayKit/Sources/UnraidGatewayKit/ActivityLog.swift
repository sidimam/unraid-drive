import Foundation

/// One sync operation performed by the File Provider extension (shown as "sync activity" on the Mac).
public struct ActivityEvent: Codable, Identifiable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case download, upload, create, folder, move, delete }
    public var id: UUID
    public var date: Date
    public var serverID: String
    public var name: String
    public var path: String
    public var kind: Kind
    public var bytes: Int64?
    public var error: String?

    public init(serverID: String, path: String, kind: Kind, bytes: Int64? = nil, error: String? = nil) {
        id = UUID(); date = Date(); self.serverID = serverID; self.path = path
        name = (path as NSString).lastPathComponent
        self.kind = kind; self.bytes = bytes; self.error = error
    }
    public var failed: Bool { error != nil }
}

/// Append-only log in the app group container, shared by the extension (writer) and the app (reader).
/// Kept to the last `limit` events; a Darwin notification tells the app when something was added.
public enum ActivityLog {
    public static let limit = 300
    public static let notificationName = "com.sdimambro.unraid-drive.activity"
    static var url: URL? { AppGroup.containerURL?.appendingPathComponent("activity.json") }
    private static let queue = DispatchQueue(label: "activity-log")

    public static func append(_ event: ActivityEvent) {
        queue.async {
            var all = load()
            all.append(event)
            if all.count > limit { all.removeFirst(all.count - limit) }
            save(all)
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notificationName as CFString), nil, nil, true)
        }
    }

    public static func recent(limit: Int = limit) -> [ActivityEvent] {
        queue.sync { Array(load().suffix(limit).reversed()) }
    }

    public static func clear() { queue.sync { save([]) } }

    private static func load() -> [ActivityEvent] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ActivityEvent].self, from: data)) ?? []
    }
    private static func save(_ events: [ActivityEvent]) {
        guard let url else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(events) { try? data.write(to: url, options: .atomic) }
    }
}
