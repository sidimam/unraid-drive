import Foundation
import FileProvider
import UniformTypeIdentifiers
import UnraidGatewayKit

/// An item as presented to the system. Wraps a gateway entry plus the stable
/// identifiers resolved through `ItemIndex`.
final class FileProviderItem: NSObject, NSFileProviderItem {
    let entry: FSEntry
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    /// True when the user's share permission is read-only.
    let readOnly: Bool

    init(entry: FSEntry, identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, readOnly: Bool = false) {
        self.entry = entry
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.readOnly = readOnly
    }

    var filename: String { entry.name }

    var contentType: UTType {
        if entry.isDirectory { return .folder }
        let ext = (entry.name as NSString).pathExtension
        return ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data)
    }

    var capabilities: NSFileProviderItemCapabilities {
        let depth = GatewayPath.depth(entry.path)
        if readOnly {
            return entry.isDirectory ? [.allowsContentEnumerating, .allowsReading] : [.allowsReading, .allowsEvicting]
        }
        if depth <= 1 {
            // A share is a mount point: browse and add, but never rename or delete it.
            return [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems]
        }
        var caps: NSFileProviderItemCapabilities = [.allowsReading, .allowsWriting, .allowsReparenting, .allowsRenaming, .allowsDeleting]
        if entry.isDirectory { caps.formUnion([.allowsAddingSubItems, .allowsContentEnumerating]) } else { caps.insert(.allowsEvicting) }
        return caps
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: Data(entry.etag.utf8), metadataVersion: Data((entry.etag + "|" + entry.name).utf8))
    }

    var documentSize: NSNumber? { entry.isDirectory ? nil : NSNumber(value: entry.size) }
    var contentModificationDate: Date? { entry.mtime }
    var creationDate: Date? { entry.mtime }
    var childItemCount: NSNumber? { nil }

}

/// The synthetic root: its children are the mounted shares.
final class RootItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { "Unraid" }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion { NSFileProviderItemVersion(contentVersion: Data("root".utf8), metadataVersion: Data("root".utf8)) }
}
