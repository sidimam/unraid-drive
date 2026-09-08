import SwiftUI
import UnraidGatewayKit

/// User-selectable colour scheme: follow the system, or force light/dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"

    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// `.preferredColorScheme` is not re-applied to sheets that are already on screen, so the
    /// override goes on the windows themselves: it takes effect immediately everywhere.
    func applyToWindows() {
        let style: UIUserInterfaceStyle
        switch self {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.overrideUserInterfaceStyle = style }
        }
    }
}

/// UI language: follow the system or force one of the bundled localizations.
/// SwiftUI text switches immediately through the environment locale; `AppleLanguages`
/// is synchronised so that formatters and code paths outside SwiftUI follow at the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case italian = "it"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case chinese = "zh-Hans"
    case arabic = "ar"
    static let key = "language"

    var id: String { rawValue }
    /// Endonym, as is customary for language pickers.
    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .italian: return "Italiano"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .chinese: return "中文（简体）"
        case .arabic: return "العربية"
        }
    }
    var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
    var isRTL: Bool { self == .arabic }

    func applySystemOverride() {
        if self == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([rawValue], forKey: "AppleLanguages") }
    }
}

/// Always sets both environment values, so switching between System and a forced language
/// never changes the view structure (a structural change would tear down presented sheets).
struct AppLocaleModifier: ViewModifier {
    let language: AppLanguage
    func body(content: Content) -> some View {
        let locale = language.locale ?? Locale.autoupdatingCurrent
        let rtl = language == .system ? Locale.Language(identifier: Locale.current.identifier).characterDirection == .rightToLeft : language.isRTL
        return content
            .environment(\.locale, locale)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}
