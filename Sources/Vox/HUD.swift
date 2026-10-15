import AppKit
import Combine
import SwiftUI

/// State for the floating pill shown at the bottom of the screen while dictating.
@MainActor
final class HUDModel: ObservableObject {
    enum Phase: Equatable {
        case hidden, recording, transcribing
        case success(String)
        case failure(String)
    }

    static let barCount = 48

    @Published var phase = Phase.hidden
    @Published var profileName = ""
    @Published var mode = RecordMode.toggle
    @Published var shortcut: Shortcut?
    @Published var levels = [CGFloat](repeating: 0, count: barCount)
    /// Text of the last successful transcription, offered by the copy button.
    var lastText = ""
    /// Called by the pill's stop button and esc hint.
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    /// Whether the cursor is over the pill; it sits at half opacity otherwise.
    @Published var hovered = false
    /// The pill's frame in the panel's content view (top-left origin), used for hover tracking.
    var pillFrame = CGRect.zero

    func beginRecording(profile: Profile, mode: RecordMode) {
        profileName = profile.name
        shortcut = profile.shortcut
        self.mode = mode
        levels = [CGFloat](repeating: 0, count: Self.barCount)
        phase = .recording
    }

    func push(level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }
}

@MainActor
final class HUDController {
    private let model: HUDModel
    private let panel: NSPanel
    private var cancellable: AnyCancellable?
    private var hideWork: DispatchWorkItem?
    private var hoverTimer: Timer?

    init(model: HUDModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))

        cancellable = model.$phase.removeDuplicates().sink { [weak self] phase in
            self?.update(for: phase)
        }
    }

    private func update(for phase: HUDModel.Phase) {
        hideWork?.cancel()
        // Only the recording (stop/cancel) and success (copy) pills have something to click.
        switch phase {
        case .recording, .success: panel.ignoresMouseEvents = false
        default: panel.ignoresMouseEvents = true
        }
        trackHover(phase != .hidden)
        switch phase {
        case .hidden:
            fade(in: false)
        case .recording, .transcribing:
            fade(in: true)
        case .success:
            fade(in: true)
            scheduleHide(after: 3)
        case .failure:
            fade(in: true)
            scheduleHide(after: 4)
        }
    }

    /// The panel mostly ignores mouse events (so it never blocks clicks), so hover is polled.
    private func trackHover(_ enabled: Bool) {
        guard enabled else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            return
        }
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        updateHover()
    }

    private func updateHover() {
        let pill = model.pillFrame
        let rect = NSRect(
            x: panel.frame.minX + pill.minX,
            y: panel.frame.maxY - pill.maxY,
            width: pill.width,
            height: pill.height
        )
        let hovered = rect.contains(NSEvent.mouseLocation)
        if hovered != model.hovered { model.hovered = hovered }
    }

    private func scheduleHide(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.model.phase = .hidden }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fade(in visible: Bool) {
        if visible && !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 20))
            }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, !visible, self.model.phase == .hidden { self.panel.orderOut(nil) }
            }
        }
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    @State private var copied = false

    var body: some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(minHeight: 40)
            .background(.black.opacity(0.88), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { model.pillFrame = frame }
                        .onChange(of: frame) { model.pillFrame = frame }
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
            .opacity(model.hovered ? 1 : 0.5)
            .animation(.easeOut(duration: 0.15), value: model.hovered)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.3), value: model.phase)
            .onChange(of: model.phase) { copied = false }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            HStack(spacing: 14) {
                VStack(spacing: 5) {
                    LevelBars(levels: model.levels)
                    HStack(spacing: 10) {
                        Text(model.profileName).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            if model.mode == .hold {
                                Text("Release")
                            } else if let shortcut = model.shortcut {
                                KeycapsView(shortcut: shortcut, compact: true)
                            }
                            Image(systemName: "checkmark")
                        }
                        .help("Finish")
                        Button(action: model.onCancel) {
                            HStack(spacing: 4) {
                                KeycapsView(shortcut: .escape, compact: true)
                                Image(systemName: "xmark")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: 280)

                Button(action: model.onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Stop and transcribe")
            }
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing…")
            }
        case .success(let message):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                Text(message).fixedSize()
                if !model.lastText.isEmpty {
                    GhostIconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy transcript") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.lastText, forType: .string)
                        copied = true
                    }
                }
            }
        case .failure(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                Text(message).lineLimit(2).frame(maxWidth: 340, alignment: .leading)
            }
        }
    }
}

/// Icon-only button that only shows a background while hovered.
private struct GhostIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.white.opacity(hovering ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct LevelBars: View {
    let levels: [CGFloat]

    private let barWidth: CGFloat = 3
    private let maxHeight: CGFloat = 26

    /// Spreads the bars evenly so the waveform spans the full width it's given.
    var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(levels.count - 1, 1))
            let spacing = max(0, (proxy.size.width - barWidth * CGFloat(levels.count)) / gaps)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: barWidth, height: 3 + levels[index] * (maxHeight - 3))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
