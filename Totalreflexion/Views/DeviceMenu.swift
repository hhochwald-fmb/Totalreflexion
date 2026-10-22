import SwiftUI

/// Per-device options, used as context menu on each device and as the "…" menu in the control window.
struct DeviceMenuItems: View {
    let device: MirroredDevice
    let store: DeviceSettingsStore
    var onRename: () -> Void = {}

    private var settings: DeviceSettings { store[device] }

    var body: some View {
        Picker("Rahmen", selection: Binding(
            get: { settings.frameStyle },
            set: { value in store.update(device) { $0.frameStyle = value } })) {
            Text("Standard").tag(FrameStyle?.none)
            Divider()
            ForEach(FrameStyle.allCases) { style in
                Text(style.title).tag(FrameStyle?.some(style))
            }
        }
        Picker("Farbe", selection: Binding(
            get: { settings.frameColor },
            set: { value in store.update(device) { $0.frameColor = value } })) {
            Text("Standard").tag(FrameColor?.none)
            Divider()
            ForEach(FrameColor.allCases) { color in
                Text(color.title).tag(FrameColor?.some(color))
            }
        }
        Divider()
        Button("Nach links drehen") { store.update(device) { $0.quarterTurns -= 1 } }
        Button("Nach rechts drehen") { store.update(device) { $0.quarterTurns += 1 } }
        Divider()
        Toggle("Ton stumm", isOn: Binding(
            get: { settings.muted },
            set: { muted in
                store.update(device) { $0.muted = muted }
                device.volumeChanged(muted ? 0 : 1)
            }))
        Button("Umbenennen …", action: onRename)
        Divider()
        Button("Verbindung trennen", role: .destructive) { device.disconnect() }
    }
}

/// Name tag, status overlay and context menu around a device.
struct DeviceChrome: ViewModifier {
    let device: MirroredDevice
    let store: DeviceSettingsStore
    let showName: Bool
    @State private var renaming = false
    @State private var newName = ""

    func body(content: Content) -> some View {
        content
            .overlay {
                if device.isSuspended {
                    Label("Bildschirm gesperrt", systemImage: "lock.fill")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                } else if !device.hasVideo {
                    ProgressView("Verbinde …")
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .overlay(alignment: .bottom) {
                if showName {
                    Text(displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 6)
                        .alignmentGuide(.bottom) { $0[.top] - 4 }
                }
            }
            .contextMenu {
                DeviceMenuItems(device: device, store: store, onRename: startRename)
            }
            .deviceRenameAlert(device, store: store, isPresented: $renaming, name: $newName)
    }

    private var displayName: String {
        store.displayName(device)
    }

    private func startRename() {
        newName = displayName
        renaming = true
    }
}

extension View {
    func deviceRenameAlert(_ device: MirroredDevice, store: DeviceSettingsStore, isPresented: Binding<Bool>,
                           name: Binding<String>) -> some View {
        alert("Gerät umbenennen", isPresented: isPresented) {
            TextField("Name", text: name)
            Button("Sichern") {
                let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespaces)
                store.update(device) { $0.alias = trimmed.isEmpty ? nil : trimmed }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

extension View {
    func deviceChrome(_ device: MirroredDevice, store: DeviceSettingsStore, showName: Bool) -> some View {
        modifier(DeviceChrome(device: device, store: store, showName: showName))
    }
}
