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

/// Alternate app icons (same artwork, different bar colour). "default" is the Unraid orange → red.
struct AppIconColor: Identifiable, Equatable {
    let key: String
    let label: LocalizedStringKey
    let tint: Color
    var id: String { key }
    static let storageKey = "iconColor"

    static let all: [AppIconColor] = [
        .init(key: "default", label: "Unraid", tint: Color(red: 1.00, green: 0.55, blue: 0.18)),
        .init(key: "rosso", label: "Red", tint: Color(red: 0.86, green: 0.22, blue: 0.22)),
        .init(key: "blu", label: "Blue", tint: Color(red: 0.24, green: 0.45, blue: 0.90)),
        .init(key: "teal", label: "Teal", tint: Color(red: 0.10, green: 0.65, blue: 0.65)),
        .init(key: "viola", label: "Purple", tint: Color(red: 0.52, green: 0.34, blue: 0.90)),
        .init(key: "grafite", label: "Graphite", tint: Color(red: 0.55, green: 0.58, blue: 0.62)),
    ]

    /// Switches the Home Screen icon (iOS/iPadOS; visionOS keeps its layered icon).
    static func apply(_ key: String) {
        #if os(iOS)
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { return }
            let name = key == "default" ? nil : "AppIcon-\(key)"
            if UIApplication.shared.alternateIconName != name {
                UIApplication.shared.setAlternateIconName(name)
            }
        }
        #endif
    }
}

/// Row of coloured dots to pick the icon colour.
struct IconColorPicker: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppIconColor.all) { c in
                Button { selection = c.key } label: {
                    ZStack {
                        Circle().fill(c.tint).frame(width: 30, height: 30)
                        if selection == c.key { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.label))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Section header in the Unraid colour instead of the default grey.
struct SectionTitle: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }
    var body: some View { Text(key).foregroundStyle(Color.accentColor) }
}

/// Navigation titles in the Unraid colour (UIKit-drawn, so styled through the appearance proxy).
enum NavigationBarStyle {
    static func apply() {
        #if os(iOS)
        let orange = UIColor(red: 1.0, green: 0.55, blue: 0.18, alpha: 1)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: orange]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: orange]
        #endif
    }
}
