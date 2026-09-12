import Foundation
import Combine
import UnraidGatewayKit

/// The explorer's own clipboard for Copy / Cut / Paste between folders of the same server (the
/// gateway copies or moves on the NAS; nothing is downloaded). Holds one selection at a time —
/// one item or many — app-wide, and pastes it item by item.
@MainActor final class ExplorerClipboard: ObservableObject {
    static let shared = ExplorerClipboard()
    struct Item: Equatable { let serverID: String; let entry: FSEntry; let cut: Bool }
    @Published private(set) var items: [Item] = []

    /// The first item, for callers that show one name.
    var item: Item? { items.first }
    var isEmpty: Bool { items.isEmpty }

    func copy(_ e: FSEntry, server: ServerConfig) { copy([e], server: server) }
    func cut(_ e: FSEntry, server: ServerConfig) { cut([e], server: server) }
    func copy(_ entries: [FSEntry], server: ServerConfig) { items = entries.map { Item(serverID: server.id, entry: $0, cut: false) } }
    func cut(_ entries: [FSEntry], server: ServerConfig) { items = entries.map { Item(serverID: server.id, entry: $0, cut: true) } }
    func clear() { items = [] }

    /// Something to paste into `folder` of `server`: the items that are not the folder itself, its
    /// parent (for a cut) or an ancestor of it. Nil when nothing applies.
    func pasteable(into folder: String, server: ServerConfig) -> Pasteable? {
        guard !items.isEmpty, items[0].serverID == server.id, folder != "/" else { return nil }
        let ok = items.filter { i in
            if GatewayPath.parent(i.entry.path) == folder && i.cut { return false }
            if i.entry.isDirectory, folder == i.entry.path || folder.hasPrefix(i.entry.path + "/") { return false }
            return true
        }
        return ok.isEmpty ? nil : Pasteable(items: ok, cut: items[0].cut)
    }
    struct Pasteable { let items: [Item]; let cut: Bool
        var count: Int { items.count }
        var entry: FSEntry { items[0].entry }
        /// "Paste Welcome.md" / "Paste 3 items" label helper.
        var label: String { count == 1 ? entry.name : String(localized: "\(count) items") }
    }

    /// Performs the paste through the gateway, one item after the other; returns the error text
    /// (one line per failed item), if any. Cut items that moved are dropped from the clipboard.
    func paste(into folder: String, server: ServerConfig, client: GatewayClient, progress: ((Int, Int) -> Void)? = nil) async -> String? {
        guard let p = pasteable(into: folder, server: server) else { return nil }
        var errors: [String] = []
        var moved: Set<String> = []
        for (n, i) in p.items.enumerated() {
            progress?(n + 1, p.items.count)
            let dest = GatewayPath.join(folder, i.entry.name)
            do {
                if i.cut { _ = try await client.move(i.entry.path, to: dest); moved.insert(i.entry.path) }
                else { _ = try await client.copy(i.entry.path, to: dest) }
            } catch { errors.append("\(i.entry.name): \(error.localizedDescription)") }
        }
        if !moved.isEmpty { items.removeAll { moved.contains($0.entry.path) } }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
}
