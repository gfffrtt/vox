import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Watches for the profiles' shortcuts using a CGEvent tap (requires Accessibility permission)
/// and swallows matching key events so the frontmost app never sees them.
final class HotkeyMonitor {
    var bindings: [(id: UUID, shortcut: Shortcut)] = []
    /// Ignore all shortcuts (e.g. while the user is recording a new one in the UI).
    var isPaused = false
    /// Swallow Esc and report it via `onEscape` (used to cancel a recording).
    var swallowEscape = false

    var onPress: (UUID) -> Void = { _ in }
    var onRelease: (UUID) -> Void = { _ in }
    var onEscape: () -> Void = {}

    private var tap: CFMachPort?
    private var held: (keyCode: Int64, id: UUID)?

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
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            if held?.keyCode == keyCode { return nil } // swallow auto-repeat while held
            guard !isPaused else { return pass }
            let modifiers = event.flags.intersection(Shortcut.relevantFlags)
            if swallowEscape, keyCode == Int64(kVK_Escape), modifiers.isEmpty {
                onEscape()
                return nil
            }
            guard let binding = bindings.first(where: {
                Int64($0.shortcut.keyCode) == keyCode && $0.shortcut.flags == modifiers
            }) else { return pass }
            held = (keyCode, binding.id)
            onPress(binding.id)
            return nil
        case .keyUp:
            guard let held, held.keyCode == keyCode else { return pass }
            self.held = nil
            onRelease(held.id)
            return nil
        default:
            return pass
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
