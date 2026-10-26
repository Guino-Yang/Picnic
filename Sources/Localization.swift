import Foundation

// Bundle chooses among packaged .lproj resources using macOS preferred languages,
// including any per-app language override. English is the development fallback.
enum L10n {
    enum Key: String, CaseIterable {
        case modeOff
        case modeAuto
        case modeManual
        case boostOff
        case ambient
        case ambientUnavailable
        case gentleTier
        case strongTier
        case gentleAccessibility
        case strongAccessibility
        case delays
        case releaseThresholds
        case iconAccessibility
        case launchAtLogin
        case approveLogin
        case loginFailed
        case loginError
        case help
        case quit
        case checkingDisplay
        case noDisplay
        case openDisplay
        case unsupportedDisplay
        case activeStatus
        case initializationFailed
        case boostDisabled
        case sensorUnavailable
        case autoWaiting
        case displayWriteFailed
        case displayReadFailed
        case displayConflict
        case gainFailed
        case displayCheckFailed
        case renderTaskFailed
        case gpuFailed
    }
    static func text(_ key: Key, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")
    }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }
    static var helpURL: URL? { Bundle.main.url(forResource: "Help", withExtension: "txt") }
    static var diagnostics: [String: Any] {
        ["language": language, "availableLanguages": Bundle.main.localizations,
         "strings": Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, text($0)) }),
         "helpPath": helpURL?.path ?? "missing",
         "ambientExample": format(.ambient, 1500.0),
         "releaseExample": format(.releaseThresholds, 900, 1800),
         "activeExample": format(.activeStatus, text(.modeAuto), "1.5×")]
    }
}
