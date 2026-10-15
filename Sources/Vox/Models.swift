import AppKit
import Carbon.HIToolbox
import SwiftUI

struct Shortcut: Codable, Hashable {
    var keyCode: UInt16
    /// Subset of CGEventFlags (see `relevantFlags`).
    var modifiers: UInt64
    var keyLabel: String

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]

    static let defaultDictation = Shortcut(
        keyCode: UInt16(kVK_ANSI_E),
        modifiers: CGEventFlags([.maskSecondaryFn, .maskCommand]).rawValue,
        keyLabel: "E"
    )

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    /// Keys macOS always reports with the fn flag set (F-keys, arrows, etc.).
    private static let implicitFnKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
    ]

    /// Keycap labels in the standard macOS order.
    var parts: [String] {
        var parts: [String] = []
        if flags.contains(.maskSecondaryFn) && !Self.implicitFnKeys.contains(Int(keyCode)) { parts.append("fn") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts
    }

    var displayString: String { parts.joined(separator: " ") }

    /// Builds a shortcut from a key event captured in the shortcut recorder.
    init?(event: NSEvent) {
        var flags: CGEventFlags = []
        let mods = event.modifierFlags
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.function) { flags.insert(.maskSecondaryFn) }
        guard !flags.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: flags.rawValue,
                  keyLabel: Self.label(for: Int(event.keyCode), characters: event.charactersIgnoringModifiers))
    }

    init(keyCode: UInt16, modifiers: UInt64, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static func label(for keyCode: Int, characters: String?) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = named[keyCode] { return name }
        let chars = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return chars.isEmpty ? "Key \(keyCode)" : chars
    }
}

enum ProfileColor: String, Codable, CaseIterable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, gray

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .gray: .gray
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var color: ProfileColor
    var shortcut: Shortcut?
    var systemPrompt: String
    /// Empty means "use the default model from Settings".
    var model: String

    static let icons = [
        "waveform", "text.bubble", "globe", "envelope", "chevron.left.forwardslash.chevron.right",
        "terminal", "sparkles", "doc.text", "pencil.line", "briefcase", "list.bullet.rectangle",
        "character.book.closed", "bubble.left.and.text.bubble.right", "brain.head.profile", "lightbulb", "megaphone",
    ]

    static func dictation(systemPrompt: String) -> Profile {
        Profile(name: "Dictation", icon: "waveform", color: .blue, shortcut: .defaultDictation,
              systemPrompt: systemPrompt, model: "")
    }

    static let defaultPrompt = "Clean up filler words (um, uh, like) and false starts. Use proper punctuation and capitalization."
}

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date: Date
    var duration: TimeInterval
    var profileID: UUID
    var profileName: String
    var profileIcon: String
    var profileColor: ProfileColor

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}
