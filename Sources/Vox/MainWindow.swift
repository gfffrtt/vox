import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let store: AppStore
    private var window: NSWindow?

    init(store: AppStore) {
        self.store = store
    }

    func show(pane: AppStore.Pane? = nil) {
        if let pane { store.pane = pane }
        if window == nil {
            let hosting = NSHostingController(rootView: MainView().environmentObject(store))
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.toolbar = NSToolbar(identifier: "VoxMain")
            window.toolbarStyle = .unified
            window.title = "Vox"
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(white: 0x12 / 255, alpha: 1)
            window.minSize = NSSize(width: 780, height: 500)
            window.setContentSize(NSSize(width: 940, height: 640))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("VoxMainWindow")
            self.window = window
        }
        // Show in the Dock and app switcher while the window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MainView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.pane) {
                Label("Home", systemImage: "house").tag(AppStore.Pane.home)
                Label("Profiles", systemImage: "person.crop.rectangle.stack").tag(AppStore.Pane.profiles)
                Label("Settings", systemImage: "gearshape").tag(AppStore.Pane.settings)
            }
            .scrollContentBackground(.hidden)
            .background(Color.voxBackground)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { StatusFooter() }
        } detail: {
            switch store.pane ?? .home {
            case .home: HomeView()
            case .profiles: ProfilesView()
            case .settings: SettingsPane()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.voxBackground)
        .toolbarBackground(Color.voxBackground, for: .windowToolbar)
        .preferredColorScheme(.dark)
    }
}

private struct StatusFooter: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.hasAPIKey {
                Button {
                    store.pane = .settings
                } label: {
                    Label("Add your API key", systemImage: "key.fill")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var status: String {
        switch store.activity {
        case .idle: "Ready"
        case .recording(let id): "Recording · \(store.profile(id)?.name ?? "")"
        case .transcribing: "Transcribing…"
        }
    }

    private var dotColor: Color {
        switch store.activity {
        case .idle: store.hasAPIKey ? .green : .orange
        case .recording: .red
        case .transcribing: .white
        }
    }
}
