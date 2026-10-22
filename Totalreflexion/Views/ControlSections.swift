import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DevicesSection: View {
    let receiver: Receiver
    let settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController

    var body: some View {
        Section {
            if receiver.devices.isEmpty {
                Text("Noch kein iPad verbunden. Auf dem iPad: Kontrollzentrum › Bildschirmsynchronisierung › "
                     + "„\(settings.receiverName)“.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(receiver.devices) { device in
                    DeviceRow(device: device, store: store, display: display)
                }
            }
        } header: {
            HStack {
                Text("iPads")
                Spacer()
                if receiver.devices.contains(where: \.isHidden) {
                    Button("Alle einblenden") {
                        receiver.devices.forEach { display.setHidden($0, false) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
    }
}

private struct DeviceRow: View {
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
            .help("Rahmen, drehen, stumm, umbenennen, trennen")
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.vertical, 2)
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
            .help(active ? "Vollbild beenden (Esc)"
                  : "Nur dieses iPad im Vollbild – gedrückt halten, um den Bildschirm zu wählen")
        } else {
            Button {
                display.toggleFullScreen(device)
            } label: {
                icon
            }
            .help(active ? "Vollbild beenden (Esc)" : "Nur dieses iPad im Vollbild")
        }
    }

    private func startRename() {
        newName = store.displayName(device)
        renaming = true
    }
}

struct FrameSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Picker("Rahmen", selection: $settings.defaultFrameStyle) {
                ForEach(FrameStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Farbe", selection: $settings.defaultFrameColor) {
                ForEach(FrameColor.allCases) { Text($0.title).tag($0) }
            }
            .disabled(settings.defaultFrameStyle == .none || settings.defaultFrameStyle == .custom)
            LabeledContent("Eigenes Rahmenbild") {
                HStack {
                    Text(settings.customFramePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Keins")
                        .foregroundStyle(.secondary)
                    Button("Wählen …") {
                        chooseImage {
                            settings.customFramePath = $0
                            settings.defaultFrameStyle = .custom
                        }
                    }
                    if settings.customFramePath != nil {
                        Button("Entfernen") { settings.customFramePath = nil }
                    }
                }
            }
            Toggle("Gerätenamen anzeigen", isOn: $settings.showNames)
        } header: {
            Text("Rahmen")
        } footer: {
            Text("Gilt für alle iPads. Einzelne iPads stellst du über „…“ in der Liste oben oder per Rechtsklick ein.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BackgroundSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Picker("Art", selection: $settings.backgroundKind) {
                ForEach(BackgroundKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if settings.backgroundKind == .image {
                LabeledContent("Bild") {
                    HStack {
                        Text(settings.backgroundImagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Keins")
                            .foregroundStyle(.secondary)
                        Button("Wählen …") { chooseImage { settings.backgroundImagePath = $0 } }
                    }
                }
                Toggle("Bild füllt den ganzen Bildschirm", isOn: $settings.backgroundImageFills)
            } else {
                ColorPicker("Farbe", selection: settings.colorBinding(\.backgroundColor))
                if settings.backgroundKind == .gradient {
                    ColorPicker("Verlauf bis", selection: settings.colorBinding(\.gradientEndColor))
                }
            }
            PresentationBackground(settings: settings)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 140)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Hintergrund der Bühne")
        } footer: {
            Text("Tipp: Eine PowerPoint-Folie als Bild exportieren und hier unter „Bild“ wählen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Network and quality settings; they apply after restarting the receiver.
struct ReceiverSection: View {
    let receiver: Receiver
    @Bindable var settings: AppSettings
    @State private var needsRestart = false

    var body: some View {
        Section {
            DisclosureGroup("Empfänger: Name, Qualität, Ton") {
                TextField("Name im AirPlay-Menü", text: $settings.receiverName)
                Picker("Max. Auflösung", selection: $settings.resolution) {
                    ForEach(StreamResolution.allCases) { Text($0.title).tag($0) }
                }
                Picker("Bildrate", selection: $settings.maxFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Ton wiedergeben", isOn: $settings.audioEnabled)
                Text("Änderungen gelten nach einem Neustart des Empfängers. Verbundene iPads werden dabei getrennt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Empfänger neu starten") {
                    receiver.restart()
                    needsRestart = false
                }
                .disabled(!needsRestart)
            }
        }
        .onChange(of: settings.resolution) { needsRestart = true }
        .onChange(of: settings.maxFPS) { needsRestart = true }
        .onChange(of: settings.audioEnabled) { needsRestart = true }
        .onChange(of: settings.receiverName) { needsRestart = true }
    }
}

extension AppSettings {
    func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, CodableColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: self[keyPath: keyPath].nsColor) },
            set: { self[keyPath: keyPath] = CodableColor(NSColor($0)) })
    }
}

@MainActor
private func chooseImage(_ completion: (String) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
        completion(url.path)
    }
}
