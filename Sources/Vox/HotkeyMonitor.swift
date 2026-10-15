import Carbon.HIToolbox
import CoreGraphics

/// Watches for fn + ⌘ + E using a CGEvent tap (requires Accessibility permission)
/// and swallows those key events so the frontmost app never sees them.
final class HotkeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var tap: CFMachPort?
    private var isDown = false

    /// Returns false if the tap could not be created (usually missing Accessibility permission).
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_E) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if isDown { return nil } // swallow auto-repeat while held
            let flags = event.flags
            guard flags.contains(.maskSecondaryFn), flags.contains(.maskCommand),
                  !flags.contains(.maskControl), !flags.contains(.maskAlternate) else {
                return Unmanaged.passUnretained(event)
            }
            isDown = true
            onPress()
            return nil
        case .keyUp:
            guard isDown else { return Unmanaged.passUnretained(event) }
            isDown = false
            onRelease()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
