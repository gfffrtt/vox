import Foundation

enum PrefKey {
    static let defaultModel = "defaultModel"
    static let recordMode = "recordMode"
    static let autoPaste = "autoPaste"
    static let playSounds = "playSounds"
    static let apiKey = "geminiAPIKey"
}

enum RecordMode: String, CaseIterable, Identifiable {
    case toggle, hold
    var id: String { rawValue }
}

/// App-wide preferences stored in UserDefaults (views bind to the same keys via @AppStorage).
enum Prefs {
    static let fallbackModel = "gemini-3.1-flash-lite"

    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.defaultModel: fallbackModel,
            PrefKey.recordMode: RecordMode.toggle.rawValue,
            PrefKey.autoPaste: true,
            PrefKey.playSounds: true,
        ])
    }

    /// Overrides the system accent color for this app only, so selections, focus rings and
    /// switches render in graphite instead of blue.
    static func applyMonochromeAccent() {
        UserDefaults.standard.set(-1, forKey: "AppleAccentColor")
        UserDefaults.standard.set("0.847059 0.847059 0.862745 Graphite", forKey: "AppleHighlightColor")
    }

    static var defaultModel: String {
        let model = UserDefaults.standard.string(forKey: PrefKey.defaultModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? fallbackModel : model
    }

    static var recordMode: RecordMode {
        RecordMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.recordMode) ?? "") ?? .toggle
    }

    static var autoPaste: Bool { UserDefaults.standard.bool(forKey: PrefKey.autoPaste) }
    static var playSounds: Bool { UserDefaults.standard.bool(forKey: PrefKey.playSounds) }

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: PrefKey.apiKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.apiKey) }
    }
}
