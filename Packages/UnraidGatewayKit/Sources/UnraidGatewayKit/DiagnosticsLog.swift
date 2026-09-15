import Foundation
import os

/// Rotating diagnostics log shared by the app, the File Provider extension and the Apple TV app.
///
/// - Files live in the app group container (`Logs/unraid-drive.log` + `.1`…`.4`), so every process
///   of the app writes to the same place and the app can show and export them. Total size is capped
///   (`maxFiles × maxFileSize`, 5 × 1 MB by default): the log never grows past that.
/// - `error`, `warning` and `info` lines are always written; `debug` lines only while the user has
///   turned on *Debug logging* in Settings › Diagnostics (flag in the app group defaults, read by
///   every process on each write so the extension follows the switch without a restart).
/// - Every line is mirrored to the unified log (`os.Logger`, subsystem `com.sdimambro.unraid-drive`).
///
/// One line per event: `2026-09-15T07:18:47.300Z [App] INFO gateway: message`.
public enum Diag {
    public enum Level: Int, Comparable, Sendable {
        case error = 0, warning, info, debug
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        var tag: String {
            switch self { case .error: "ERROR"; case .warning: "WARN "; case .info: "INFO "; case .debug: "DEBUG" }
        }
    }

    public static let subsystem = "com.sdimambro.unraid-drive"
    /// App group defaults key of the *Debug logging* switch.
    public static let debugKey = "diagnostics.debug"
    public static let maxFileSize = 1_000_000
    public static let maxFiles = 5
    static let fileName = "unraid-drive.log"

    /// "App", "File Provider", "Apple TV": set once per process (defaults to `GatewayClient.component`).
    nonisolated(unsafe) public static var process: String?

    private static let queue = DispatchQueue(label: "com.sdimambro.unraid-drive.diag", qos: .utility)
    nonisolated(unsafe) private static var loggers: [String: Logger] = [:]
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Directory holding the rotated files (app group container, or Caches when unavailable).
    public static var directory: URL {
        let base = AppGroup.containerURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Logs", isDirectory: true)
    }
    static var currentFile: URL { directory.appendingPathComponent(fileName) }

    /// True while *Debug logging* is on.
    public static var debugEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: debugKey) }
        set {
            AppGroup.defaults.set(newValue, forKey: debugKey)
            info("diagnostics", "debug logging \(newValue ? "on" : "off")")
        }
    }

    // MARK: Writing

    public static func error(_ category: String, _ message: String) { log(.error, category, message) }
    public static func warning(_ category: String, _ message: String) { log(.warning, category, message) }
    public static func info(_ category: String, _ message: String) { log(.info, category, message) }
    /// Written only while debug logging is on; `message` is evaluated lazily.
    public static func debug(_ category: String, _ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        log(.debug, category, message())
    }
    /// Convenience for caught errors: adds the Swift description when it differs from the localized one.
    public static func error(_ category: String, _ context: String, _ error: Error) {
        let ns = error as NSError
        let loc = error.localizedDescription
        let desc = String(describing: error)
        let extra = desc == loc ? "" : " (\(desc))"
        log(.error, category, "\(context): \(loc)\(extra) [\(ns.domain) \(ns.code)]")
    }

    public static func log(_ level: Level, _ category: String, _ message: String) {
        let proc = process ?? GatewayClient.component
        let line = "\(stamp.string(from: Date())) [\(proc)] \(level.tag) \(category): \(message.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        let logger = osLogger(category)
        switch level {
        case .error: logger.error("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .info: logger.notice("\(message, privacy: .public)")
        case .debug: logger.debug("\(message, privacy: .public)")
        }
        queue.async { append(line) }
    }

    private static func osLogger(_ category: String) -> Logger {
        queue.sync {
            if let l = loggers[category] { return l }
            let l = Logger(subsystem: subsystem, category: category)
            loggers[category] = l
            return l
        }
    }

    private static func append(_ line: String) {
        let fm = FileManager.default
        let dir = directory
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        let url = currentFile
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int), size >= maxFileSize { rotate() }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(line.utf8))
    }

    /// unraid-drive.log → .1 → .2 … the oldest (`.maxFiles-1`) is dropped.
    private static func rotate() {
        let fm = FileManager.default
        let dir = directory
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let from = dir.appendingPathComponent(i == 1 ? fileName : "\(fileName).\(i - 1)")
            let to = dir.appendingPathComponent("\(fileName).\(i)")
            try? fm.removeItem(at: to)
            if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: to) }
        }
    }

    // MARK: Reading / exporting

    /// The rotated files, oldest first, that exist right now.
    public static func files() -> [URL] {
        let dir = directory
        var out: [URL] = []
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let u = dir.appendingPathComponent("\(fileName).\(i)")
            if FileManager.default.fileExists(atPath: u.path) { out.append(u) }
        }
        if FileManager.default.fileExists(atPath: currentFile.path) { out.append(currentFile) }
        return out
    }

    /// Total bytes on disk.
    public static func totalSize() -> Int {
        files().reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0) }
    }

    /// The last `count` lines across the rotated files (newest last).
    public static func tail(_ count: Int = 300) -> [String] {
        queue.sync {
            var lines: [String] = []
            for u in files().reversed() {
                guard let s = try? String(contentsOf: u, encoding: .utf8) else { continue }
                let part = s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                lines.insert(contentsOf: part, at: 0)
                if lines.count >= count { break }
            }
            return Array(lines.suffix(count))
        }
    }

    public static func clear() {
        queue.sync { for u in files() { try? FileManager.default.removeItem(at: u) } }
        info("diagnostics", "log cleared")
    }

    /// One plain-text file with every rotated file concatenated (oldest first), preceded by a
    /// header the caller supplies (device, app, servers…). Written to the temporary directory.
    public static func export(header: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Unraid-Drive-diagnostics-\(Int(Date().timeIntervalSince1970)).log")
        var text = header.hasSuffix("\n") ? header : header + "\n"
        text += "\n===== log (\(files().count) file, \(totalSize()) bytes) =====\n"
        queue.sync {
            for u in files() {
                text += "\n----- \(u.lastPathComponent) -----\n"
                text += (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            }
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
