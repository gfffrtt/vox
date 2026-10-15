import Foundation
import Security

enum SettingsKey {
    static let model = "model"
    static let systemPrompt = "systemPrompt"
    static let translate = "translate"
    static let targetLanguage = "targetLanguage"
    static let autoPaste = "autoPaste"
    static let mode = "mode"
}

enum Defaults {
    static let model = "gemini-3.8-flash"
    static let systemPrompt = """
    Clean up filler words (um, uh, like) and false starts. Use proper punctuation and capitalization.
    """
    static let targetLanguage = "English"
}

enum RecordMode: String {
    case hold, toggle
}

/// Snapshot of the user's settings, read from UserDefaults (the settings UI writes via @AppStorage).
struct Settings {
    var model: String
    var systemPrompt: String
    var translate: Bool
    var targetLanguage: String
    var autoPaste: Bool
    var mode: RecordMode

    static func current() -> Settings {
        let d = UserDefaults.standard
        d.register(defaults: [
            SettingsKey.model: Defaults.model,
            SettingsKey.systemPrompt: Defaults.systemPrompt,
            SettingsKey.translate: false,
            SettingsKey.targetLanguage: Defaults.targetLanguage,
            SettingsKey.autoPaste: true,
            SettingsKey.mode: RecordMode.hold.rawValue,
        ])
        let model = d.string(forKey: SettingsKey.model)?.trimmingCharacters(in: .whitespaces) ?? ""
        return Settings(
            model: model.isEmpty ? Defaults.model : model,
            systemPrompt: d.string(forKey: SettingsKey.systemPrompt) ?? "",
            translate: d.bool(forKey: SettingsKey.translate),
            targetLanguage: d.string(forKey: SettingsKey.targetLanguage) ?? Defaults.targetLanguage,
            autoPaste: d.bool(forKey: SettingsKey.autoPaste),
            mode: RecordMode(rawValue: d.string(forKey: SettingsKey.mode) ?? "") ?? .hold
        )
    }
}

/// Stores the Gemini API key in the login keychain.
enum APIKeyStore {
    private static let service = "Vox"
    private static let account = "gemini-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
