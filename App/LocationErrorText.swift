import Foundation
import FileProvider
import UnraidGatewayKit
#if os(macOS)
import AppKit
#endif

/// Turns the errors of `NSFileProviderManager` into words a user can act on, instead of the system's
/// generic text ("The application cannot be used right now" for `providerNotFound`, which is what
/// appears when the extension is switched off after an update).
enum LocationErrorText {
    enum Kind { case extensionUnavailable, translocated, otherVersionRunning, domainDisabled, temporarilyUnavailable, other }

    static func kind(of error: Error) -> Kind {
        let ns = error as NSError
        guard ns.domain == NSFileProviderErrorDomain else { return .other }
        switch NSFileProviderError.Code(rawValue: ns.code) {
        case .providerNotFound: return .extensionUnavailable
        case .providerTranslocated: return .translocated
        case .olderExtensionVersionRunning, .newerExtensionVersionFound: return .otherVersionRunning
        case .providerDomainTemporarilyUnavailable: return .temporarilyUnavailable
        default:
            #if os(macOS)
            if #available(macOS 13, *), NSFileProviderError.Code(rawValue: ns.code) == .domainDisabled { return .domainDisabled }
            #endif
            return .other
        }
    }

    /// One-line explanation for status rows and the connection test.
    static func describe(_ error: Error) -> String {
        switch kind(of: error) {
        case .extensionUnavailable:
            #if os(macOS)
            return String(localized: "The Unraid Drive extension is switched off. Turn it on in System Settings › General › Login Items & Extensions › File Providers, then try again.")
            #else
            return String(localized: "The Unraid Drive extension is switched off. In the Files app open Browse › ⋯ › Edit and turn on Unraid Drive, then try again.")
            #endif
        case .translocated:
            return String(localized: "Unraid Drive is running from a temporary location. Move the app to the Applications folder and open it from there.")
        case .otherVersionRunning:
            return String(localized: "Another version of the Unraid Drive extension is still running. Quit the app, wait a moment and open it again (or restart the device).")
        case .domainDisabled:
            return String(localized: "The location is disabled in System Settings › General › Login Items & Extensions › File Providers.")
        case .temporarilyUnavailable:
            return String(localized: "The location is temporarily unavailable; the system is still setting it up. Try again in a minute.")
        case .other:
            let ns = error as NSError
            return "\(error.localizedDescription) [\(ns.domain) \(ns.code)]"
        }
    }

    /// True when the remedy is a switch the user has to flip, not something the app can repeat.
    static func needsUserAction(_ error: Error) -> Bool {
        switch kind(of: error) {
        case .extensionUnavailable, .translocated, .domainDisabled: return true
        default: return false
        }
    }

    #if os(macOS)
    /// The System Settings pane where File Provider extensions are enabled.
    static let extensionsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
    static func openExtensionsSettings() { NSWorkspace.shared.open(extensionsSettingsURL) }
    #endif
}
