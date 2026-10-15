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

    static let barCount = 18

    @Published var phase = Phase.hidden
    @Published var profileName = ""
    @Published var profileIcon = "waveform"
    @Published var profileColor = ProfileColor.blue
    @Published var startedAt = Date()
    @Published var mode = RecordMode.toggle
    @Published var levels = [CGFloat](repeating: 0, count: barCount)

    func beginRecording(profile: Profile, mode: RecordMode) {
        profileName = profile.name
        profileIcon = profile.icon
        profileColor = profile.color
        startedAt = Date()
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
        switch phase {
        case .hidden:
            fade(in: false)
        case .recording, .transcribing:
            fade(in: true)
        case .success:
            fade(in: true)
            scheduleHide(after: 1.4)
        case .failure:
            fade(in: true)
            scheduleHide(after: 4)
        }
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

    var body: some View {
        content
            .font(.system(size: 13, weight: .medium))
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(height: 48)
            .glassCapsule()
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.3), value: model.phase)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            HStack(spacing: 12) {
                ProfileIconView(symbol: model.profileIcon, color: model.profileColor, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.profileName).font(.system(size: 13, weight: .semibold))
                    Text(model.mode == .toggle ? "Press shortcut to finish · esc to cancel" : "Release to finish · esc to cancel")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                LevelBars(levels: model.levels, color: model.profileColor.color)
                TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                    Text(elapsed(since: model.startedAt, now: context.date))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                RecordingDot()
            }
        case .transcribing:
            HStack(spacing: 10) {
                ProfileIconView(symbol: model.profileIcon, color: model.profileColor, size: 30)
                ProgressView().controlSize(.small)
                Text("Transcribing…")
            }
        case .success(let message):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                Text(message)
            }
            .padding(.leading, 6)
        case .failure(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 16))
                Text(message).lineLimit(2).frame(maxWidth: 340, alignment: .leading)
            }
            .padding(.leading, 6)
        }
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LevelBars: View {
    let levels: [CGFloat]
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(color.gradient)
                    .frame(width: 3, height: 4 + levels[index] * 20)
            }
        }
        .frame(height: 24)
        .animation(.linear(duration: 0.08), value: levels)
    }
}

private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a material capsule on older systems.
    @ViewBuilder func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            materialCapsule()
        }
        #else
        materialCapsule()
        #endif
    }

    private func materialCapsule() -> some View {
        self
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}
