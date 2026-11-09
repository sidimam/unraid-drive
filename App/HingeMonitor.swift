#if os(iOS)
import SwiftUI
import UIKit
import UnraidGatewayKit

/// Hinge posture of the iPhone Duo (and of any future foldable). Build 49, same design as
/// aMule Remote 1.5. `unknown` = no hinge on this device, or no update received yet.
enum HingeStatus: String {
    case unknown, closed, partiallyOpen, fullyOpen
}

/// Hinge state observed by SwiftUI. Fed by `HingeObserverView` (UIHingeInteraction, iOS 27.1+) or by
/// the launch argument `-hinge closed|partial|open`, for regression runs and screenshots on the
/// simulator, whose posture cannot be changed from the command line.
@MainActor
final class HingeMonitor: ObservableObject {
    static let shared = HingeMonitor()

    @Published private(set) var status: HingeStatus = .unknown
    /// Angle in radians (0 = closed, π = fully open); nil when unknown.
    @Published private(set) var angle: Double?

    /// True when the posture is forced by `-hinge` (tests).
    let forced: Bool

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-hinge"), i + 1 < args.count {
            forced = true
            switch args[i + 1] {
            case "closed": status = .closed; angle = 0
            case "partial", "half": status = .partiallyOpen; angle = .pi / 2
            case "open": status = .fullyOpen; angle = .pi
            default: status = .unknown
            }
        } else {
            forced = false
        }
    }

    func update(status: HingeStatus, angle: Double?) {
        guard !forced else { return }
        if self.status != status {
            self.status = status
            Diag.info("layout", "hinge → \(status.rawValue)")
        }
        self.angle = angle
    }

    /// "Laptop" posture: the phone half open and standing, the fold splitting the inner display
    /// into a top half and a bottom half.
    var isLaptopPosture: Bool { status == .partiallyOpen }
}

/// Invisible view that attaches `UIHingeInteraction` to the hierarchy and forwards its updates to
/// `HingeMonitor`. Does nothing on systems without the API or without a hinge.
struct HingeObserverView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.isHidden = true
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    Task { @MainActor in HingeMonitor.shared.update(status: .unknown, angle: nil) }
                    return
                }
                let status: HingeStatus
                switch hinge.status {
                case .closed: status = .closed
                case .partiallyOpen: status = .partiallyOpen
                case .fullyOpen: status = .fullyOpen
                default: status = .unknown
                }
                let angle = Double(hinge.angle)
                Task { @MainActor in HingeMonitor.shared.update(status: status, angle: angle) }
            }
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
