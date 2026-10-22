import AppKit
import SwiftUI

/// The one window that controls everything: which view shows the iPads, each iPad, frames, background
/// and the receiver. The views themselves only show the devices.
struct ControlView: View {
    let receiver: Receiver
    @Bindable var settings: AppSettings
    let store: DeviceSettingsStore
    @Bindable var display: DisplayController
    @State private var window: NSWindow?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                StatusBadge(receiver: receiver)
                Spacer()
                HelpButton(topic: .views)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Form {
                Section("Ansicht") {
                    Picker("Ansicht", selection: $settings.viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.viewMode.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ViewModeOptions(settings: settings, store: store, display: display) { show(settings.viewMode) }
                }
                DevicesSection(receiver: receiver, settings: settings, store: store, display: display)
                FrameSection(settings: settings)
                if settings.viewMode == .stage {
                    BackgroundSection(settings: settings)
                }
                ReceiverSection(receiver: receiver, settings: settings)
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 440, minHeight: 480)
        .background(WindowAccessor { window = $0 })
        .onChange(of: settings.viewMode) { _, mode in show(mode) }
        .onAppear {
            guard !display.didHandleLaunch else { return }
            display.didHandleLaunch = true
            show(settings.viewMode)
            if !UserDefaults.standard.bool(forKey: "helpShown") {
                UserDefaults.standard.set(true, forKey: "helpShown")
                openWindow(id: "help")
            }
        }
    }

    /// Opens the window of a view and closes the others, so exactly one view is active.
    private func show(_ mode: ViewMode) {
        for other in ViewMode.allCases where other != mode {
            if let id = other.windowID {
                dismissWindow(id: id)
            }
        }
        guard let id = mode.windowID else { return }
        openWindow(id: id)
        // The new window opens in front; keep the controls reachable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [window] in
            window?.orderFront(nil)
        }
    }
}

/// Options that only make sense for the active view.
private struct ViewModeOptions: View {
    @Bindable var settings: AppSettings
    let store: DeviceSettingsStore
    @Bindable var display: DisplayController
    let reopen: () -> Void

    var body: some View {
        switch settings.viewMode {
        case .grid:
            WindowRow(display: display, reopen: reopen)
        case .stage:
            WindowRow(display: display, reopen: reopen)
            Toggle("Anordnung fixieren", isOn: $display.stageLocked)
                .help("Sperrt die iPads gegen versehentliches Verschieben")
            LabeledContent("Anordnung") {
                Button("Automatisch anordnen") {
                    withAnimation(.spring(duration: 0.5)) { store.resetLayout() }
                }
            }
        case .floating:
            Toggle("Immer im Vordergrund", isOn: $settings.floatOnTop)
                .help("Die iPads bleiben über anderen Apps sichtbar, z. B. über einer PowerPoint-Präsentation.")
            LabeledContent("Anordnung") {
                Button("Automatisch anordnen", action: display.arrange)
            }
        }
    }
}

/// Show, move and full-screen the grid or stage window.
private struct WindowRow: View {
    let display: DisplayController
    let reopen: () -> Void

    var body: some View {
        LabeledContent("Fenster") {
            HStack {
                Button("Zeigen", action: reopen)
                    .help("Holt das Fenster nach vorne oder öffnet es wieder, falls es geschlossen wurde")
                if NSScreen.screens.count > 1 {
                    Menu("Bildschirm") {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Button(screen.localizedName.isEmpty ? "Bildschirm \(index + 1)" : screen.localizedName) {
                                display.moveOutput(to: screen)
                            }
                        }
                    }
                    .fixedSize()
                    .help("Fenster im Vollbild auf diesen Bildschirm (z. B. Beamer) legen")
                }
                Button("Vollbild") { display.toggleOutputFullScreen() }
                    .help("Vollbild ein/aus – Esc beendet es auch")
            }
        }
    }
}

struct StatusBadge: View {
    let receiver: Receiver

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(receiver.statusDescription).font(.callout)
        }
        .help("AirPlay-Empfänger")
    }

    private var color: Color {
        switch receiver.status {
        case .running: .green
        case .starting: .yellow
        case .stopped: .gray
        case .failed: .red
        }
    }
}

/// Menu bar icon: status and the way back to the control window when it is closed.
struct MenuBarContent: View {
    let receiver: Receiver
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(receiver.statusDescription)
        Divider()
        Button("Steuerung öffnen") {
            openWindow(id: "control")
            NSApp.activate()
        }
        Divider()
        Button("Totalreflexion beenden") { NSApp.terminate(nil) }
    }
}

/// ⌘, leads to the control window as well; there is no separate settings window.
struct ControlCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") { openWindow(id: "control") }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
