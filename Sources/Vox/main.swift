import AppKit

// Must run before NSApplication reads the accent color.
Prefs.applyMonochromeAccent()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
