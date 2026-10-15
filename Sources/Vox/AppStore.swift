import Foundation

/// Shared app state for the window, menu bar and recording flow. Profiles and history persist as JSON
/// in ~/Library/Application Support/Vox.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    enum Pane: Hashable { case home, profiles, settings }
    enum Activity: Equatable { case idle, recording(UUID), transcribing(UUID) }

    @Published var pane: Pane? = .home
    @Published var selectedProfileID: UUID?
    @Published var profiles: [Profile] { didSet { save(profiles, to: "profiles.json") } }
    @Published var history: [Transcript] { didSet { save(history, to: "history.json") } }
    @Published var activity = Activity.idle
    @Published var isCapturingShortcut = false
    @Published private(set) var apiKey: String
    var hasAPIKey: Bool { !apiKey.isEmpty }

    @Published private(set) var models: [String] = []
    @Published private(set) var modelsError: String?
    @Published private(set) var loadingModels = false

    private let historyLimit = 500

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Vox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        apiKey = Prefs.apiKey
        history = Self.load([Transcript].self, from: "history.json") ?? []
        if let saved = Self.load([Profile].self, from: "profiles.json"), !saved.isEmpty {
            profiles = saved
        } else {
            // First launch (or upgrade from the single-prompt version): seed the Dictation profile.
            let oldPrompt = UserDefaults.standard.string(forKey: "systemPrompt")
            let profile = Profile.dictation(systemPrompt: oldPrompt ?? Profile.defaultPrompt)
            profiles = [profile]
            save(profiles, to: "profiles.json")
        }
        selectedProfileID = profiles.first?.id
    }

    func profile(_ id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    // MARK: Profiles

    @discardableResult
    func addProfile() -> Profile {
        let color = ProfileColor.allCases[profiles.count % ProfileColor.allCases.count]
        let profile = Profile(name: "New Profile", icon: "sparkles", color: color, shortcut: nil,
                          systemPrompt: "", model: "")
        profiles.append(profile)
        selectedProfileID = profile.id
        return profile
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let neighbor = profiles.indices.contains(index + 1) ? profiles[index + 1] : profiles[index - 1]
        selectedProfileID = neighbor.id
        profiles.remove(at: index)
    }

    // MARK: History

    func addTranscript(_ transcript: Transcript) {
        history.insert(transcript, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
    }

    func deleteTranscript(_ id: UUID) {
        history.removeAll { $0.id == id }
    }

    func clearHistory() {
        history.removeAll()
    }

    // MARK: API key & models

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != apiKey else { return }
        Prefs.apiKey = trimmed
        apiKey = trimmed
    }

    func refreshModels() async {
        guard hasAPIKey, !loadingModels else { return }
        let key = apiKey
        loadingModels = true
        defer { loadingModels = false }
        do {
            models = try await GeminiClient.listModels(apiKey: key)
            modelsError = nil
        } catch {
            modelsError = "Couldn't load models: \(error.localizedDescription)"
        }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: Self.directory.appendingPathComponent(file), options: .atomic)
    }

    private static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
