import AppIntents
import Foundation
import UniformTypeIdentifiers
import UnraidGatewayKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Entities

/// A configured server, selectable in Shortcuts.
struct ServerEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Unraid server")
    static var defaultQuery = ServerQuery()
    let id: String
    let name: String
    let url: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(url)") }

    init(_ s: ServerConfig) { id = s.id; name = s.name; url = s.url.host ?? s.url.absoluteString }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        ServerStore().all().filter { identifiers.contains($0.id) }.map(ServerEntity.init)
    }
    func suggestedEntities() async throws -> [ServerEntity] { ServerStore().all().map(ServerEntity.init) }
    func defaultResult() async -> ServerEntity? { ServerStore().all().first { !$0.isDemo }.map(ServerEntity.init) ?? ServerStore().all().first.map(ServerEntity.init) }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noServer, noCredentials, emptyClipboard, notFound(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noServer: return "No server is configured in Unraid Drive."
        case .noCredentials: return "The API key for this server is missing on this device. Open Unraid Drive to enter it."
        case .emptyClipboard: return "The clipboard is empty."
        case .notFound(let p): return "Nothing found at \(p)."
        }
    }
}

private enum Gateway {
    static func client(_ server: ServerEntity?) throws -> (ServerConfig, GatewayClient) {
        let store = ServerStore()
        guard let s = (server.flatMap { store.server(id: $0.id) } ?? store.all().first(where: { !$0.isDemo }) ?? store.all().first) else { throw IntentError.noServer }
        guard let c = GatewayClientFactory.client(for: s) else { throw IntentError.noCredentials }
        return (s, c)
    }
    /// "documents/Notes" → "/documents/Notes"
    static func normalize(_ folder: String) -> String {
        var f = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.hasPrefix("/") { f = "/" + f }
        while f.count > 1 && f.hasSuffix("/") { f.removeLast() }
        return f
    }
    static func uniqueName(_ base: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return base.replacingOccurrences(of: "{date}", with: df.string(from: Date()))
    }
}

// MARK: - Intents

struct SaveClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Save clipboard to Unraid Drive"
    static var description = IntentDescription("Saves the clipboard (text, image or file) as a new file in a share of your Unraid server.")
    static var openAppWhenRun = false

    @Parameter(title: "Server") var server: ServerEntity?
    @Parameter(title: "Folder", description: "Share and folder, e.g. documents/Notes", default: "documents") var folder: String
    @Parameter(title: "File name", description: "Without extension; {date} is replaced by the current date and time", default: "Clipboard {date}") var fileName: String

    static var parameterSummary: some ParameterSummary { Summary("Save the clipboard to \(\.$folder) on \(\.$server)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (_, client) = try Gateway.client(server)
        let base = Gateway.uniqueName(fileName)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var name: String
        #if os(macOS)
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let u = urls.first, u.isFileURL {
            try FileManager.default.copyItem(at: u, to: tmp); name = u.lastPathComponent
        } else if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: tmp); name = base + ".png"
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            try text.write(to: tmp, atomically: true, encoding: .utf8); name = base + ".txt"
        } else { throw IntentError.emptyClipboard }
        #else
        let pb = UIPasteboard.general
        if let img = pb.image, let png = img.pngData() {
            try png.write(to: tmp); name = base + ".png"
        } else if let url = pb.url, !url.isFileURL {
            try url.absoluteString.write(to: tmp, atomically: true, encoding: .utf8); name = base + ".url.txt"
        } else if let text = pb.string, !text.isEmpty {
            try text.write(to: tmp, atomically: true, encoding: .utf8); name = base + ".txt"
        } else { throw IntentError.emptyClipboard }
        #endif
        defer { try? FileManager.default.removeItem(at: tmp) }
        let path = Gateway.normalize(folder) + "/" + name
        _ = try await client.upload(fileURL: tmp, to: path, overwrite: false)
        return .result(value: path)
    }
}

struct UploadFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Upload file to Unraid Drive"
    static var description = IntentDescription("Uploads a file to a share of your Unraid server.")
    @Parameter(title: "File") var file: IntentFile
    @Parameter(title: "Server") var server: ServerEntity?
    @Parameter(title: "Folder", description: "Share and folder, e.g. media/Photos", default: "documents") var folder: String
    @Parameter(title: "Replace if it exists", default: false) var overwrite: Bool
    static var parameterSummary: some ParameterSummary { Summary("Upload \(\.$file) to \(\.$folder) on \(\.$server)") { \.$overwrite } }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (_, client) = try Gateway.client(server)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try file.data.write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        let path = Gateway.normalize(folder) + "/" + (file.filename.isEmpty ? "File \(Gateway.uniqueName("{date}"))" : file.filename)
        _ = try await client.upload(fileURL: tmp, to: path, overwrite: overwrite)
        return .result(value: path)
    }
}

struct DownloadFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Get file from Unraid Drive"
    static var description = IntentDescription("Downloads a file from a share of your Unraid server and passes it on.")
    @Parameter(title: "Server") var server: ServerEntity?
    @Parameter(title: "Path", description: "Share and path of the file, e.g. documents/report.pdf") var path: String
    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$path) from \(\.$server)") }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (_, client) = try Gateway.client(server)
        let p = Gateway.normalize(path)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { _ = try await client.download(p, to: tmp) } catch GatewayError.notFound { throw IntentError.notFound(p) }
        let data = try Data(contentsOf: tmp); try? FileManager.default.removeItem(at: tmp)
        let name = (p as NSString).lastPathComponent
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        return .result(value: IntentFile(data: data, filename: name, type: type))
    }
}

struct ListFolderIntent: AppIntent {
    static var title: LocalizedStringResource = "List folder on Unraid Drive"
    static var description = IntentDescription("Returns the names of the files and folders in a share folder.")
    @Parameter(title: "Server") var server: ServerEntity?
    @Parameter(title: "Folder", description: "Share and folder, e.g. documents; empty for the list of shares", default: "") var folder: String
    static var parameterSummary: some ParameterSummary { Summary("List \(\.$folder) on \(\.$server)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let (config, client) = try Gateway.client(server)
        let path = Gateway.normalize(folder)
        let page = try await client.list(path)
        let entries = path == "/" ? page.entries.filter { config.isVisible(path: $0.path) } : page.entries
        return .result(value: entries.map { $0.isDirectory ? $0.name + "/" : $0.name })
    }
}

struct RefreshLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Unraid Drive locations"
    static var description = IntentDescription("Asks the Files app / Finder to re-read every Unraid Drive location from the gateway.")
    func perform() async throws -> some IntentResult {
        for s in ServerStore().all() where !s.isDemo { await FileProviderDomains.signal(s) }
        return .result()
    }
}

struct TestConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Test Unraid Drive connection"
    static var description = IntentDescription("Checks that the gateway answers and the API key is accepted.")
    @Parameter(title: "Server") var server: ServerEntity?
    static var parameterSummary: some ParameterSummary { Summary("Test the connection to \(\.$server)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let (s, client) = try Gateway.client(server)
        do {
            let h = try await client.health(); _ = try await client.login()
            return .result(value: true, dialog: "\(s.name) is reachable (gateway \(h.version ?? "?")) and the key is accepted.")
        } catch {
            return .result(value: false, dialog: "\(s.name): \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcuts / Siri

struct UnraidDriveShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SaveClipboardIntent(), phrases: ["Save the clipboard to \(.applicationName)", "Save clipboard with \(.applicationName)"],
                    shortTitle: "Save clipboard", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: UploadFileIntent(), phrases: ["Upload a file to \(.applicationName)"],
                    shortTitle: "Upload file", systemImageName: "arrow.up.doc")
        AppShortcut(intent: DownloadFileIntent(), phrases: ["Get a file from \(.applicationName)"],
                    shortTitle: "Get file", systemImageName: "arrow.down.doc")
        AppShortcut(intent: ListFolderIntent(), phrases: ["List a folder on \(.applicationName)"],
                    shortTitle: "List folder", systemImageName: "list.bullet")
        AppShortcut(intent: RefreshLocationIntent(), phrases: ["Refresh \(.applicationName)", "Sync \(.applicationName)"],
                    shortTitle: "Refresh", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: TestConnectionIntent(), phrases: ["Test \(.applicationName) connection", "Is \(.applicationName) reachable"],
                    shortTitle: "Test connection", systemImageName: "stethoscope")
    }
}
