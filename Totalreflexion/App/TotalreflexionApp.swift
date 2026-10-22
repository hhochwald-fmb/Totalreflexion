import SwiftUI

@main
struct TotalreflexionApp: App {
    @State private var settings: AppSettings
    @State private var store: DeviceSettingsStore
    @State private var receiver: Receiver
    @State private var display: DisplayController
    @State private var help = HelpNavigator()

    init() {
        let settings = AppSettings()
        let store = DeviceSettingsStore()
        let receiver = Receiver(settings: settings, deviceSettings: store)
        let display = DisplayController(receiver: receiver, settings: settings, store: store)
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _receiver = State(initialValue: receiver)
        _display = State(initialValue: display)
        // Started here rather than by a window, since any window may be closed.
        Task { @MainActor in
            receiver.start()
            display.start()
        }
    }

    var body: some Scene {
        // The control window opens at launch and then opens the active view.
        Window("Totalreflexion", id: "control") {
            ControlView(receiver: receiver, settings: settings, store: store, display: display)
                .environment(help)
        }
        .defaultSize(width: 480, height: 780)
        .defaultPosition(.topTrailing)
        .keyboardShortcut("1", modifiers: .command)
        .commands {
            ControlCommands()
            HelpCommands(navigator: help)
        }

        // The views are opened and closed by the control window only, hence not in the Window menu.
        Window("Raster", id: "grid") {
            GridView(receiver: receiver, settings: settings, store: store, display: display)
                .environment(help)
        }
        .defaultSize(width: 1200, height: 800)
        .commandsRemoved()

        Window("Bühne", id: "stage") {
            StageView(receiver: receiver, settings: settings, store: store, display: display)
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()

        Window("Totalreflexion-Hilfe", id: "help") {
            HelpView()
                .environment(help)
        }
        .defaultSize(width: 940, height: 680)

        MenuBarExtra("Totalreflexion", systemImage: "airplayvideo") {
            MenuBarContent(receiver: receiver)
        }
    }
}
