import SwiftUI

/// Main window: all mirrored devices in an automatic grid, zoomable, with a focus mode for one device.
struct OverviewView: View {
    let receiver: Receiver
    @Bindable var settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController
    @State private var zoom = ZoomController()
    @State private var focusedID: UUID?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.0)
            if receiver.devices.isEmpty {
                EmptyStateView(receiver: receiver, settings: settings)
            } else if receiver.visibleDevices.isEmpty {
                Text("Alle iPads sind ausgeblendet.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                ZoomableView(controller: zoom) {
                    DeviceGrid(receiver: receiver, settings: settings, store: store, focusedID: focusedID) { id in
                        withAnimation(.spring(duration: 0.35)) {
                            focusedID = focusedID == id ? nil : id
                        }
                        zoom.reset()
                    }
                }
            }
        }
        .background(.black.opacity(0.85))
        .frame(minWidth: 640, minHeight: 420)
        .toolbar { toolbar }
        .onChange(of: receiver.visibleDevices.map(\.id)) { _, ids in
            if let focusedID, !ids.contains(focusedID) {
                self.focusedID = nil
            }
        }
        .onExitCommand {
            withAnimation { focusedID = nil }
            zoom.reset()
        }
        .onAppear {
            // In "Eigene Fenster" mode the app starts without the main window.
            guard !display.didHandleLaunch else { return }
            display.didHandleLaunch = true
            if !UserDefaults.standard.bool(forKey: "helpShown") {
                UserDefaults.standard.set(true, forKey: "helpShown")
                openWindow(id: "help")
            }
            if settings.floatingWindows {
                openWindow(id: "manager")
                dismissWindow(id: "main")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StatusBadge(receiver: receiver)
        }
        ToolbarItemGroup {
            if focusedID != nil {
                Button {
                    withAnimation { focusedID = nil }
                    zoom.reset()
                } label: {
                    Label("Alle zeigen", systemImage: "square.grid.2x2")
                }
            }
            Menu {
                Picker("Standard-Rahmen", selection: $settings.defaultFrameStyle) {
                    ForEach(FrameStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Standard-Farbe", selection: $settings.defaultFrameColor) {
                    ForEach(FrameColor.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Namen anzeigen", isOn: $settings.showNames)
            } label: {
                Label("Rahmen", systemImage: settings.defaultFrameStyle == .none ? "rectangle" : "ipad")
            }
            ControlGroup {
                Button { zoom.zoom(by: 1 / 1.4) } label: { Label("Verkleinern", systemImage: "minus.magnifyingglass") }
                    .keyboardShortcut("-", modifiers: .command)
                Button { zoom.reset() } label: { Text("\(Int(zoom.magnification * 100)) %").monospacedDigit() }
                    .keyboardShortcut("0", modifiers: .command)
                Button { zoom.zoom(by: 1.4) } label: { Label("Vergrößern", systemImage: "plus.magnifyingglass") }
                    .keyboardShortcut("+", modifiers: .command)
            }
            Button {
                openWindow(id: "manager")
            } label: {
                Label("Geräte", systemImage: "list.bullet.rectangle")
            }
            .help("Geräte verwalten: ein- und ausblenden, Vollbild, eigene Fenster")
            Button {
                openWindow(id: "presentation")
            } label: {
                Label("Präsentation", systemImage: "play.rectangle.on.rectangle")
            }
            .help("Präsentation öffnen (⇧⌘P)")
        }
    }
}

private struct DeviceGrid: View {
    let receiver: Receiver
    let settings: AppSettings
    let store: DeviceSettingsStore
    let focusedID: UUID?
    let toggleFocus: (UUID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let visible = receiver.visibleDevices
            let devices = focusedID.flatMap { id in visible.filter { $0.id == id } } ?? visible
            let appearances = devices.map { DeviceAppearance(device: $0, settings: settings, store: store) }
            let labelSpace: CGFloat = settings.showNames ? 34 : 0
            let padding: CGFloat = 24
            let bounds = CGSize(width: proxy.size.width - padding * 2,
                                height: proxy.size.height - padding * 2 - labelSpace)
            let aspects = zip(devices, appearances).map { $1.totalAspect(for: $0) }
            let frames = GridLayout.layout(aspects: aspects, in: bounds, spacing: 28 + labelSpace).frames
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(devices, appearances).enumerated()), id: \.element.0.id) { index, pair in
                    if index < frames.count {
                        let frame = frames[index]
                        DeviceView(device: pair.0, appearance: pair.1)
                            .frame(width: frame.width, height: frame.height)
                            .deviceChrome(pair.0, store: store, showName: settings.showNames)
                            .onTapGesture(count: 2) { toggleFocus(pair.0.id) }
                            .position(x: frame.midX + padding, y: frame.midY + padding)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.spring(duration: 0.4), value: frames.map(\.integral))
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
        .padding(.horizontal, 8)
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

private struct EmptyStateView: View {
    let receiver: Receiver
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("Warte auf iPads …")
                .font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Label("iPad und Mac im selben WLAN", systemImage: "wifi")
                Label("Auf dem iPad das Kontrollzentrum öffnen", systemImage: "switch.2")
                Label("„Bildschirmsynchronisierung“ antippen", systemImage: "rectangle.on.rectangle")
                Label("„\(settings.receiverName)“ auswählen", systemImage: "checkmark.circle")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            Text("Mehrere iPads können sich gleichzeitig verbinden.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            HelpButton(title: "So funktioniert Totalreflexion")
                .buttonStyle(.bordered)
                .colorScheme(.dark)
        }
        .foregroundStyle(.white)
        .padding(40)
    }
}
