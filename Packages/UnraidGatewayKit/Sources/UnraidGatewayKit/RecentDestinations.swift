import Foundation

/// Destinations of recent move/copy/share operations, per server (app group), used as shortcuts.
public enum RecentDestinations {
    private static func key(_ server: String) -> String { "explorer.recentDestinations." + server }
    private static let keep = 10

    public static func record(_ path: String, server: String) {
        var all = (AppGroup.defaults.dictionary(forKey: key(server)) as? [String: [String: Any]]) ?? [:]
        var e = all[path] ?? [:]
        e["count"] = ((e["count"] as? Int) ?? 0) + 1
        e["last"] = Date().timeIntervalSince1970
        all[path] = e
        if all.count > keep {
            let victims = all.sorted { (($0.value["last"] as? Double) ?? 0) < (($1.value["last"] as? Double) ?? 0) }.prefix(all.count - keep)
            for v in victims { all.removeValue(forKey: v.key) }
        }
        AppGroup.defaults.set(all, forKey: key(server))
    }

    /// Paths used twice or more, most recent first.
    public static func shortcuts(server: String) -> [String] {
        let all = (AppGroup.defaults.dictionary(forKey: key(server)) as? [String: [String: Any]]) ?? [:]
        return all.filter { (($0.value["count"] as? Int) ?? 0) >= 2 }
            .sorted { (($0.value["last"] as? Double) ?? 0) > (($1.value["last"] as? Double) ?? 0) }
            .map(\.key)
    }
}

public extension RecentDestinations {
    /// Every recent destination, most recent first (the share extension proposes the last one).
    static func all(server: String) -> [String] {
        let all = (AppGroup.defaults.dictionary(forKey: "explorer.recentDestinations." + server) as? [String: [String: Any]]) ?? [:]
        return all.sorted { (($0.value["last"] as? Double) ?? 0) > (($1.value["last"] as? Double) ?? 0) }.map(\.key)
    }
}
