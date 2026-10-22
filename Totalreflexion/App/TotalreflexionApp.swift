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
        // Started here rather than by a window, since the app may run without its main window.
        Task { @MainActor in
            receiver.start()
            display.start()
        }
    }

    var body: some Scene {
        Window("Totalreflexion", id: "main") {
            OverviewView(receiver: receiver, settings: settings, store: store, display: display)
                .environment(help)
        }
        .defaultSize(width: 1200, height: 800)
        .commands { HelpCommands(navigator: help) }

        Window("Geräte", id: "manager") {
            ManagerView(receiver: receiver, settings: settings, store: store, display: display)
                .environment(help)
        }
        .defaultSize(width: 460, height: 520)
        .keyboardShortcut("g", modifiers: [.command, .shift])

        Window("Präsentation", id: "presentation") {
            PresentationView(receiver: receiver, settings: settings, store: store)
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Window("Totalreflexion-Hilfe", id: "help") {
            HelpView()
                .environment(help)
        }
        .defaultSize(width: 940, height: 680)

        MenuBarExtra("Totalreflexion", systemImage: "airplayvideo") {
            MenuBarContent(receiver: receiver, settings: settings, store: store, display: display)
                .environment(help)
        }

        Settings {
            SettingsView(receiver: receiver, settings: settings)
        }
    }
}
