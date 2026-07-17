import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case germanAustria = "de-AT"
    case germanGermany = "de-DE"
    case germanSwitzerland = "de-CH"
    case germanLiechtenstein = "de-LI"
    case italian = "it"
    case english = "en"

    static let storageKey = "appLanguagePreference"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Systemeinstellung"
        case .germanAustria: "Deutsch (Österreich)"
        case .germanGermany: "Deutsch (Deutschland)"
        case .germanSwitzerland: "Deutsch (Schweiz)"
        case .germanLiechtenstein: "Deutsch (Liechtenstein)"
        case .italian: "Italienisch"
        case .english: "Englisch"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        default:
            Locale(identifier: rawValue)
        }
    }
}
