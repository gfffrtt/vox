import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.model) private var model = Defaults.model
    @AppStorage(SettingsKey.systemPrompt) private var systemPrompt = Defaults.systemPrompt
    @AppStorage(SettingsKey.translate) private var translate = false
    @AppStorage(SettingsKey.targetLanguage) private var targetLanguage = Defaults.targetLanguage
    @AppStorage(SettingsKey.autoPaste) private var autoPaste = true
    @AppStorage(SettingsKey.mode) private var mode = RecordMode.hold.rawValue

    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelsError: String?

    var body: some View {
        Form {
            Section("Gemini") {
                SecureField("API key", text: $apiKey)
                    .onChange(of: apiKey) { _, newValue in APIKeyStore.save(newValue) }
                Link("Get an API key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)

                HStack {
                    TextField("Model", text: $model, prompt: Text(Defaults.model))
                    Menu("Choose") {
                        ForEach(models, id: \.self) { id in
                            Button(id) { model = id }
                        }
                    }
                    .fixedSize()
                    .disabled(models.isEmpty)
                    Button {
                        Task { await refreshModels() }
                    } label: {
                        if loadingModels { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }
                    .help("Load available models")
                    .disabled(apiKey.isEmpty || loadingModels)
                }
                if let modelsError {
                    Text(modelsError).font(.caption).foregroundStyle(.red)
                }
                Button("Reset to default model") { model = Defaults.model }
                    .font(.caption)
                    .buttonStyle(.link)
            }

            Section {
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 120)
            } header: {
                Text("System prompt")
            } footer: {
                Text("Context about you and how the text should come out, e.g. \"I'm a software engineer; keep technical terms like Kubernetes, PostgreSQL and React exact.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Translation") {
                Toggle("Translate the transcript", isOn: $translate)
                TextField("Target language", text: $targetLanguage)
                    .disabled(!translate)
            }

            Section("Behavior") {
                Picker("fn ⌘ E", selection: $mode) {
                    Text("Hold to talk").tag(RecordMode.hold.rawValue)
                    Text("Press to start / stop").tag(RecordMode.toggle.rawValue)
                }
                Toggle("Paste into the active app (otherwise copy only)", isOn: $autoPaste)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            if !apiKey.isEmpty { await refreshModels() }
        }
    }

    private func refreshModels() async {
        loadingModels = true
        defer { loadingModels = false }
        do {
            models = try await GeminiClient.listModels(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            modelsError = nil
        } catch {
            modelsError = "Couldn't load models: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Vox Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
