import AppKit
import SwiftUI

extension Color {
    /// Off-black window background.
    static let voxBackground = Color(white: 0x12 / 255)
    /// Slightly lifted surface for cards.
    static let voxSurface = Color(white: 0x1B / 255)
}

struct KeycapsView: View {
    let shortcut: Shortcut
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            ForEach(Array(shortcut.parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: compact ? 10 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(compact ? .secondary : .primary)
                    .padding(.horizontal, compact ? 4 : 6)
                    .frame(minWidth: compact ? 16 : 22, minHeight: compact ? 16 : 22)
                    .background(RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous).fill(.quaternary.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous).strokeBorder(.separator))
            }
        }
    }
}

/// Click, then press a key combination to record it. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @EnvironmentObject private var store: AppStore
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Group {
                    if isRecording {
                        Text("Press keys…").foregroundStyle(.primary)
                    } else if let shortcut {
                        KeycapsView(shortcut: shortcut)
                    } else {
                        Text("Record Shortcut").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 130, minHeight: 26)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isRecording ? Color.primary.opacity(0.8) : Color.primary.opacity(0.12), lineWidth: isRecording ? 2 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if shortcut != nil && !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        store.isCapturingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            guard let captured = Shortcut(event: event) else {
                NSSound.beep() // needs at least one modifier (fn, ⌃, ⌥, ⇧ or ⌘)
                return nil
            }
            shortcut = captured
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        store.isCapturingShortcut = false
    }
}

/// Dropdown of the models available to the API key.
struct ModelPicker: View {
    let title: String
    @Binding var model: String
    /// When set, adds a "Default (…)" option that stores an empty string.
    var defaultModel: String?
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Picker(title, selection: $model) {
                if let defaultModel {
                    Text("Default (\(defaultModel))").tag("")
                    Divider()
                }
                // Keep the saved value selectable even if it isn't in the loaded list.
                if !model.isEmpty && !store.models.contains(model) {
                    Text(store.models.isEmpty ? model : "\(model) (unavailable)").tag(model)
                }
                ForEach(store.models, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            if let error = store.modelsError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !store.hasAPIKey {
                Text("Add an API key to load models").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            if store.models.isEmpty { await store.refreshModels() }
        }
    }
}

extension View {
    /// Rounded card used across the main window.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.voxSurface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}
