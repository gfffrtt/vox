import AVFoundation
import ApplicationServices
import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(PrefKey.defaultModel) private var defaultModel = Prefs.fallbackModel
    @AppStorage(PrefKey.recordMode) private var recordMode = RecordMode.toggle
    @AppStorage(PrefKey.autoPaste) private var autoPaste = true
    @AppStorage(PrefKey.playSounds) private var playSounds = true

    @State private var apiKey = AppStore.shared.apiKey
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var confirmClear = false

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("API key") {
                    SecureField("API key", text: $apiKey, prompt: Text("Paste your Gemini API key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(minWidth: 260)
                        .onChange(of: apiKey) { _, newValue in
                            store.setAPIKey(newValue)
                            Task { await store.refreshModels() }
                        }
                }
                ModelPicker(title: "Default model", model: $defaultModel)
            } header: {
                Text("Gemini")
            } footer: {
                HStack(spacing: 4) {
                    Text("The default model is used by profiles that don't pick their own.")
                    Link("Get an API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Recording") {
                Picker("Shortcut behavior", selection: $recordMode) {
                    Text("Press to start, press again to stop").tag(RecordMode.toggle)
                    Text("Hold to talk").tag(RecordMode.hold)
                }
                .pickerStyle(.radioGroup)
                Toggle("Paste into the active app", isOn: $autoPaste)
                Toggle("Play sounds", isOn: $playSounds)
            }

            Section("Permissions") {
                PermissionRow(title: "Accessibility", detail: "Global shortcuts and auto-paste",
                              symbol: "accessibility", granted: accessibilityGranted,
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                PermissionRow(title: "Microphone", detail: "Recording your voice",
                              symbol: "mic", granted: microphoneGranted,
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }

            Section("Data") {
                LabeledContent("History") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(store.history.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
        .confirmationDialog("Clear all transcription history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let settingsURL: String

    var body: some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}
