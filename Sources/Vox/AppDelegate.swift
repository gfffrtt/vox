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
        setUpMainMenu()
        setUpStatusItem()
        hudController = HUDController(model: hud)
        hud.onStop = { [weak self] in self?.finishIfRecording() }
        hud.onCancel = { [weak self] in self?.cancelRecording() }

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

        // Open the window on first launch (or until an API key is set) before any permission
        // prompts, so the app comes to the front instead of only appearing in the menu bar.
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: PrefKey.hasLaunched)
        UserDefaults.standard.set(true, forKey: PrefKey.hasLaunched)
        if isFirstLaunch || !store.hasAPIKey {
            mainWindow.show(pane: store.hasAPIKey ? .home : .settings)
        }

        startHotkey()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    // MARK: Menu bar

    /// Text fields only receive ⌘C/⌘V/⌘X/⌘A/⌘Z through key equivalents in the main menu,
    /// which an accessory app doesn't get by default.
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Vox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

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
        case .transcribing: button.contentTintColor = nil
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

    private func finishIfRecording() {
        if case .recording = store.activity { finishRecording() }
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
        let apiKey = store.apiKey
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
                hud.lastText = text
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
