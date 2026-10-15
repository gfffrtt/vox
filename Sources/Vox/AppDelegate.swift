import AppKit
import AVFoundation
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore.shared
    private let hud = HUDModel()
    private var hudController: HUDController!
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private lazy var mainWindow = MainWindowController(store: store)

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let copyLastItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "")
    private var accessibilityTimer: Timer?
    private var levelTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activeProfile: Profile?

    /// Recordings shorter than this are treated as accidental presses.
    private let minimumDuration: TimeInterval = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        NSApp.applicationIconImage = AppIcon.make()
        setUpStatusItem()
        hudController = HUDController(model: hud)

        hotkey.onPress = { [weak self] id in MainActor.assumeIsolated { self?.shortcutPressed(id) } }
        hotkey.onRelease = { [weak self] id in MainActor.assumeIsolated { self?.shortcutReleased(id) } }
        hotkey.onEscape = { [weak self] in MainActor.assumeIsolated { self?.cancelRecording() } }

        store.$profiles
            .sink { [weak self] profiles in
                self?.hotkey.bindings = profiles.compactMap { profile in profile.shortcut.map { (profile.id, $0) } }
            }
            .store(in: &cancellables)
        store.$isCapturingShortcut
            .sink { [weak self] capturing in self?.hotkey.isPaused = capturing }
            .store(in: &cancellables)
        store.$activity
            .sink { [weak self] activity in self?.updateStatusIcon(activity) }
            .store(in: &cancellables)
        store.$history
            .sink { [weak self] history in self?.copyLastItem.isEnabled = !history.isEmpty }
            .store(in: &cancellables)

        startHotkey()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        if !store.hasAPIKey {
            mainWindow.show(pane: .settings)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Vox", #selector(openHome), "o"))
        copyLastItem.target = self
        menu.addItem(copyLastItem)
        menu.addItem(menuItem("Settings…", #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateStatusIcon(.idle)
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateStatusIcon(_ activity: AppStore.Activity) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch activity {
        case .idle: symbol = "waveform"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vox")
        switch activity {
        case .idle: button.contentTintColor = nil
        case .recording: button.contentTintColor = .systemRed
        case .transcribing: button.contentTintColor = .controlAccentColor
        }
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        statusItem.button?.toolTip = text
    }

    @objc private func openHome() { mainWindow.show(pane: .home) }
    @objc private func openSettings() { mainWindow.show(pane: .settings) }

    @objc private func copyLast() {
        guard let last = store.history.first else { return }
        Paster.deliver(last.text, autoPaste: false)
    }

    // MARK: Permissions

    private func startHotkey() {
        if hotkey.start() {
            setStatus("Ready")
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
                self.setStatus("Ready")
            }
        }
    }

    // MARK: Recording flow

    private func shortcutPressed(_ id: UUID) {
        switch store.activity {
        case .idle:
            startRecording(id)
        case .recording(let current) where current == id && Prefs.recordMode == .toggle:
            finishRecording()
        default:
            break
        }
    }

    private func shortcutReleased(_ id: UUID) {
        if Prefs.recordMode == .hold, case .recording(let current) = store.activity, current == id {
            finishRecording()
        }
    }

    private func startRecording(_ id: UUID) {
        guard let profile = store.profile(id) else { return }
        guard store.hasAPIKey else {
            fail("Add your Gemini API key in Settings.")
            mainWindow.show(pane: .settings)
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            fail("Vox needs microphone access. Enable it in System Settings.")
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }
        do {
            try recorder.start()
        } catch {
            fail(error.localizedDescription)
            return
        }
        activeProfile = profile
        store.activity = .recording(id)
        hotkey.swallowEscape = true
        hud.beginRecording(profile: profile, mode: Prefs.recordMode)
        setStatus("Recording · \(profile.name)")
        play("Tink")
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hud.push(level: self.recorder.level())
            }
        }
    }

    private func endRecording() -> (data: Data, duration: TimeInterval)? {
        levelTimer?.invalidate()
        levelTimer = nil
        hotkey.swallowEscape = false
        return recorder.stop()
    }

    private func cancelRecording() {
        _ = endRecording()
        activeProfile = nil
        store.activity = .idle
        hud.phase = .hidden
        setStatus("Ready")
    }

    private func finishRecording() {
        let audio = endRecording()
        guard let profile = activeProfile, let audio else {
            cancelRecording()
            return
        }
        activeProfile = nil
        play("Pop")
        guard audio.duration >= minimumDuration else {
            cancelRecording()
            return
        }

        store.activity = .transcribing(profile.id)
        hud.phase = .transcribing
        setStatus("Transcribing…")
        let customModel = profile.model.trimmingCharacters(in: .whitespaces)
        let model = customModel.isEmpty ? Prefs.defaultModel : customModel
        let apiKey = APIKeyStore.load() ?? ""
        let autoPaste = Prefs.autoPaste

        Task {
            do {
                let text = try await GeminiClient.transcribe(wav: audio.data, apiKey: apiKey, model: model, profile: profile)
                store.activity = .idle
                setStatus("Ready")
                guard !text.isEmpty else {
                    hud.phase = .failure("No speech detected")
                    return
                }
                store.addTranscript(Transcript(
                    text: text, date: Date(), duration: audio.duration,
                    profileID: profile.id, profileName: profile.name, profileIcon: profile.icon, profileColor: profile.color
                ))
                Paster.deliver(text, autoPaste: autoPaste)
                hud.phase = .success(autoPaste ? "Pasted" : "Copied to clipboard")
            } catch {
                store.activity = .idle
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        setStatus("Error: \(message)")
        hud.phase = .failure(message)
        play("Basso")
    }

    private func play(_ sound: String) {
        if Prefs.playSounds { NSSound(named: sound)?.play() }
    }
}

/// Draws the app icon at runtime (shown in the Dock while the window is open).
enum AppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 40, dy: 40)
            let path = NSBezierPath(roundedRect: inset, xRadius: 100, yRadius: 100)
            NSGradient(colors: [
                NSColor(red: 0.36, green: 0.42, blue: 1.0, alpha: 1),
                NSColor(red: 0.62, green: 0.31, blue: 0.95, alpha: 1),
            ])?.draw(in: path, angle: -60)

            let config = NSImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}
