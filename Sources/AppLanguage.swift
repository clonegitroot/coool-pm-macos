import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english, german

    var locale: Locale {
        switch self {
        case .system:
            if let language = Locale.preferredLanguages.first, language.lowercased().hasPrefix("de") {
                return Locale(identifier: language)
            }
            return Locale(identifier: "en")
        case .english: return Locale(identifier: "en")
        case .german: return Locale(identifier: "de")
        }
    }

    static func currentText(_ key: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage").flatMap(Self.init(rawValue:)) ?? .system
        return text(key, fallback: key, locale: language.locale)
    }

    static func text(_ key: String, fallback: String, locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let localized = Bundle(path: path) {
            return localized.localizedString(forKey: key, value: fallback, table: nil)
        }
        return fallback
    }
}


enum AppAppearance: String {
    case system, light, dark
}
