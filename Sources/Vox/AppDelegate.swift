import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, transcribing }

    private var state = State.idle { didSet { updateStatusIcon() } }
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let settingsWindow = SettingsWindowController()

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Ready — hold fn ⌘ E to dictate", action: nil, keyEquivalent: "")
    private let copyLastItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "")
    private var lastTranscript: String?
    private var accessibilityTimer: Timer?

    /// Recordings shorter than this are treated as accidental presses.
    private let minimumDuration: TimeInterval = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        hotkey.onPress = { [weak self] in MainActor.assumeIsolated { self?.hotkeyPressed() } }
        hotkey.onRelease = { [weak self] in MainActor.assumeIsolated { self?.hotkeyReleased() } }
        startHotkey()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        if APIKeyStore.load() == nil {
            settingsWindow.show()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        copyLastItem.target = self
        copyLastItem.isEnabled = false
        menu.addItem(copyLastItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch state {
        case .idle: symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "waveform"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vox")
        button.contentTintColor = state == .recording ? .systemRed : nil
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        statusItem.button?.toolTip = text
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func copyLast() {
        guard let lastTranscript else { return }
        Paster.deliver(lastTranscript, autoPaste: false)
    }

    // MARK: Permissions

    private func startHotkey() {
        if hotkey.start() {
            setStatus(readyMessage())
            return
        }
        // Prompts the user to grant Accessibility, then polls until it's granted.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        setStatus("Waiting for Accessibility permission…")
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hotkey.start() else { return }
                timer.invalidate()
                self.setStatus(self.readyMessage())
            }
        }
    }

    private func readyMessage() -> String {
        Settings.current().mode == .hold ? "Ready — hold fn ⌘ E to dictate" : "Ready — press fn ⌘ E to dictate"
    }

    // MARK: Recording flow

    private func hotkeyPressed() {
        switch (Settings.current().mode, state) {
        case (_, .idle): startRecording()
        case (.toggle, .recording): finishRecording()
        default: break
        }
    }

    private func hotkeyReleased() {
        if Settings.current().mode == .hold, state == .recording {
            finishRecording()
        }
    }

    private func startRecording() {
        guard APIKeyStore.load() != nil else {
            fail("Add your Gemini API key in Settings.")
            settingsWindow.show()
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            fail("Microphone access is required (System Settings → Privacy & Security → Microphone).")
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }
        do {
            try recorder.start()
            state = .recording
            setStatus("Recording…")
            NSSound(named: "Tink")?.play()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let audio = recorder.stop() else {
            state = .idle
            return
        }
        NSSound(named: "Pop")?.play()
        guard audio.duration >= minimumDuration else {
            state = .idle
            setStatus(readyMessage())
            return
        }

        state = .transcribing
        setStatus("Transcribing…")
        let settings = Settings.current()
        let apiKey = APIKeyStore.load() ?? ""

        Task {
            do {
                let text = try await GeminiClient.transcribe(wav: audio.data, apiKey: apiKey, settings: settings)
                state = .idle
                if text.isEmpty {
                    setStatus("No speech detected")
                } else {
                    lastTranscript = text
                    copyLastItem.isEnabled = true
                    Paster.deliver(text, autoPaste: settings.autoPaste)
                    setStatus(readyMessage())
                }
            } catch {
                state = .idle
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        setStatus("Error: \(message)")
        NSSound(named: "Basso")?.play()
    }
}
