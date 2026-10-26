import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}

let expected = ProcessInfo.processInfo.environment["PICNIC_EXPECT_LANGUAGE"]!
let keys = Set(L10n.Key.allCases.map(\.rawValue))
let formatPattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:\.\d+)?[@df]"#)
func placeholders(_ value: String) -> [String] {
    formatPattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
        .map { String(value[Range($0.range, in: value)!]) }.sorted()
}
var translations: [String: [String: String]] = [:]
for language in ["en", "ja", "zh-Hans"] {
    let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language)!
    let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
    expect(Set(values.keys) == keys, "Missing or extra localization keys: \(language)")
    expect(values.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Empty translation: \(language)")
    translations[language] = values
}
for key in L10n.Key.allCases {
    for language in ["ja", "zh-Hans"] {
        expect(placeholders(translations[language]![key.rawValue]!) == placeholders(translations["en"]![key.rawValue]!), "Format arguments differ: \(language)/\(key)")
    }
}

expect(L10n.language == expected, "Expected \(expected), resolved \(L10n.language)")
expect(Set(Bundle.main.localizations) == Set(["en", "ja", "zh-Hans"]), "Bundle must advertise all three languages")
for key in L10n.Key.allCases {
    expect(L10n.text(key) == translations[expected]![key.rawValue]!, "Wrong language for \(key)")
}
let release = L10n.format(.releaseThresholds, 900, 1800)
let numberFormatter = NumberFormatter()
numberFormatter.locale = Locale.current
numberFormatter.numberStyle = .decimal
func number(_ value: Int) -> String { numberFormatter.string(from: NSNumber(value: value))! }
expect(release.contains(number(900)) && release.contains(number(1800)) && !release.contains("%"), "Both release thresholds must interpolate")
let ambient = L10n.format(.ambient, 1500.0)
expect(ambient.contains(number(1500)) && !ambient.contains("%"), "Ambient light must interpolate")
let active = L10n.format(.activeStatus, L10n.text(.modeAuto), "1.5×")
expect(active.contains(L10n.text(.modeAuto)) && active.contains("1.5×") && !active.contains("%"), "Status must interpolate both arguments")
expect(L10n.format(.loginError, "example error").contains("example error"), "Underlying system error must remain available")
let help = L10n.helpURL!
expect(help.deletingLastPathComponent().lastPathComponent == "\(expected).lproj", "Help must match menu language")
let helpText = try String(contentsOf: help, encoding: .utf8)
expect(helpText.contains("https://github.com/Guino-Yang/Picnic"), "Localized help must contain project link")
print("PASS: \(checks) localization checks; preferred \(UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []) → \(expected)")
