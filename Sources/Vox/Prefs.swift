import Foundation
import Security

enum PrefKey {
    static let defaultModel = "defaultModel"
    static let recordMode = "recordMode"
    static let autoPaste = "autoPaste"
    static let playSounds = "playSounds"
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

    static var defaultModel: String {
        let model = UserDefaults.standard.string(forKey: PrefKey.defaultModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? fallbackModel : model
    }

    static var recordMode: RecordMode {
        RecordMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.recordMode) ?? "") ?? .toggle
    }

    static var autoPaste: Bool { UserDefaults.standard.bool(forKey: PrefKey.autoPaste) }
    static var playSounds: Bool { UserDefaults.standard.bool(forKey: PrefKey.playSounds) }
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
