import SwiftUI
import UnraidGatewayKit
#if os(macOS)
import AppKit

/// Host of the share sheet on the Mac.
final class ShareViewController: NSViewController {
    override func loadView() {
        Diag.process = "Share Extension"
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let root = ShareView(items: items, onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil) },
                             onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) })
        let host = NSHostingController(rootView: root)
        view = host.view
        addChild(host)
        preferredContentSize = NSSize(width: 480, height: 460)
    }
}
#else
import UIKit

/// Host of the share sheet on iPhone, iPad and Vision Pro.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Diag.process = "Share Extension"
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let root = ShareView(items: items, onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil) },
                             onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
#endif
