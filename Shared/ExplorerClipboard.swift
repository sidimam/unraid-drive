import Foundation
import Combine
import UnraidGatewayKit

/// The explorer's own clipboard for Copy / Cut / Paste between folders of the same server (the
/// gateway copies or moves on the NAS; nothing is downloaded). One item at a time, app-wide.
@MainActor final class ExplorerClipboard: ObservableObject {
    static let shared = ExplorerClipboard()
    struct Item: Equatable { let serverID: String; let entry: FSEntry; let cut: Bool }
    @Published var item: Item?

    func copy(_ e: FSEntry, server: ServerConfig) { item = Item(serverID: server.id, entry: e, cut: false) }
    func cut(_ e: FSEntry, server: ServerConfig) { item = Item(serverID: server.id, entry: e, cut: true) }
    func clear() { item = nil }

    /// Something to paste into `folder` of `server`: not the item itself, its parent, or a folder inside it.
    func pasteable(into folder: String, server: ServerConfig) -> Item? {
        guard let i = item, i.serverID == server.id, folder != "/" else { return nil }
        if GatewayPath.parent(i.entry.path) == folder && i.cut { return nil }
        if i.entry.isDirectory, folder == i.entry.path || folder.hasPrefix(i.entry.path + "/") { return nil }
        return i
    }

    /// Performs the paste through the gateway; returns the error text, if any.
    func paste(into folder: String, server: ServerConfig, client: GatewayClient) async -> String? {
        guard let i = pasteable(into: folder, server: server) else { return nil }
        let dest = GatewayPath.join(folder, i.entry.name)
        do {
            if i.cut { _ = try await client.move(i.entry.path, to: dest); item = nil }
            else { _ = try await client.copy(i.entry.path, to: dest) }
            return nil
        } catch { return error.localizedDescription }
    }
}
