import AppKit
import SwiftUI

/// "Geräte" window: all connected iPads with show/hide, full screen and per-device options,
/// plus the switch between the main window and one borderless window per iPad.
struct ManagerView: View {
    let receiver: Receiver
    @Bindable var settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(16)
            Divider()
            if receiver.devices.isEmpty {
                ContentUnavailableView("Keine iPads verbunden", systemImage: "ipad.landscape",
                                       description: Text("Auf dem iPad „Bildschirmsynchronisierung“ antippen "
                                                         + "und „\(settings.receiverName)“ wählen."))
                    .frame(maxHeight: .infinity)
            } else {
                List(receiver.devices) { device in
                    ManagedDeviceRow(device: device, store: store, display: display)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, minHeight: 340)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(receiver: receiver)
                Spacer()
                HelpButton(topic: .views)
            }
            Picker("Anzeige", selection: Binding(get: { settings.floatingWindows }, set: setFloating)) {
                Text("Hauptfenster").tag(false)
                Text("Eigene Fenster").tag(true)
            }
            .pickerStyle(.segmented)
            .help("„Eigene Fenster“: jedes iPad schwebt frei auf dem Bildschirm, ohne Hauptfenster")
            if settings.floatingWindows {
                Toggle("Immer im Vordergrund", isOn: $settings.floatOnTop)
                    .help("Die iPads bleiben über anderen Apps sichtbar, z. B. über einer PowerPoint-Präsentation.")
            }
            HStack {
                Button("Alle einblenden") {
                    receiver.devices.forEach { display.setHidden($0, false) }
                }
                .disabled(!receiver.devices.contains(where: \.isHidden))
                if settings.floatingWindows {
                    Button("Anordnen", action: display.arrange)
                        .help("Alle iPad-Fenster nebeneinander auf dem Bildschirm verteilen")
                } else {
                    Button("Hauptfenster") { openWindow(id: "main") }
                }
                Spacer()
                Button {
                    openWindow(id: "presentation")
                } label: {
                    Label("Präsentation", systemImage: "play.rectangle.on.rectangle")
                }
            }
        }
    }

    private func setFloating(_ floating: Bool) {
        settings.floatingWindows = floating
        if floating {
            dismissWindow(id: "main")
        } else {
            openWindow(id: "main")
        }
    }
}

private struct ManagedDeviceRow: View {
    let device: MirroredDevice
    let store: DeviceSettingsStore
    let display: DisplayController
    @State private var renaming = false
    @State private var newName = ""

    private var quarterTurns: Int { ((store[device].quarterTurns % 4) + 4) % 4 }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(device))
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                display.setHidden(device, !device.isHidden)
            } label: {
                Image(systemName: device.isHidden ? "eye.slash" : "eye")
                    .frame(width: 22)
            }
            .help(device.isHidden ? "Einblenden" : "Ausblenden")
            fullScreenButton
                .disabled(device.isHidden)
            Menu {
                DeviceMenuItems(device: device, store: store, onRename: startRename)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.vertical, 4)
        .contextMenu {
            DeviceMenuItems(device: device, store: store, onRename: startRename)
        }
        .deviceRenameAlert(device, store: store, isPresented: $renaming, name: $newName)
    }

    private var thumbnail: some View {
        let aspect = quarterTurns % 2 == 1 ? 1 / device.aspectRatio : device.aspectRatio
        return RotatedVideo(device: device, quarterTurns: quarterTurns)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(device.isHidden ? 0.3 : 1)
    }

    private var detail: String {
        let state = if !device.hasVideo {
            "Verbinde …"
        } else if device.isSuspended {
            "Gesperrt"
        } else {
            device.isPortrait ? "Hochformat" : "Querformat"
        }
        let hidden = device.isHidden ? " · ausgeblendet" : ""
        return "\(device.model) · \(state)\(hidden)"
    }

    @ViewBuilder private var fullScreenButton: some View {
        let active = display.fullScreenID == device.id
        let icon = Image(systemName: active ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            .frame(width: 22)
        if NSScreen.screens.count > 1 {
            Menu {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    Button("Vollbild auf „\(screen.localizedName.isEmpty ? "Bildschirm \(index + 1)" : screen.localizedName)“") {
                        display.toggleFullScreen(device, on: screen)
                    }
                }
            } label: {
                icon
            } primaryAction: {
                display.toggleFullScreen(device)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(active ? "Vollbild beenden (Esc)" : "Vollbild – gedrückt halten, um den Bildschirm zu wählen")
        } else {
            Button {
                display.toggleFullScreen(device)
            } label: {
                icon
            }
            .help(active ? "Vollbild beenden (Esc)" : "Vollbild")
        }
    }

    private func startRename() {
        newName = store.displayName(device)
        renaming = true
    }
}

/// Menu bar icon, so the app stays reachable when no window is open.
struct MenuBarContent: View {
    let receiver: Receiver
    let settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController
    @Environment(HelpNavigator.self) private var help
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Text(receiver.statusDescription)
        if !receiver.devices.isEmpty {
            Divider()
            ForEach(receiver.devices) { device in
                Toggle(store.displayName(device), isOn: Binding(
                    get: { !device.isHidden },
                    set: { display.setHidden(device, !$0) }))
            }
        }
        Divider()
        Toggle("Eigene Fenster (ohne Hauptfenster)", isOn: Binding(
            get: { settings.floatingWindows },
            set: { floating in
                settings.floatingWindows = floating
                if floating {
                    dismissWindow(id: "main")
                } else {
                    show("main")
                }
            }))
        Button("Geräte verwalten …") { show("manager") }
        Button("Hauptfenster") { show("main") }
        Button("Präsentation") { show("presentation") }
        Divider()
        SettingsLink { Text("Einstellungen …") }
        Button("Hilfe") {
            help.topic = .overview
            show("help")
        }
        Button("Totalreflexion beenden") { NSApp.terminate(nil) }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
