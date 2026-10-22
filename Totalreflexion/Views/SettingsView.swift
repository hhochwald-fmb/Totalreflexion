import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let receiver: Receiver
    @Bindable var settings: AppSettings
    @State private var needsRestart = false

    var body: some View {
        TabView {
            receiverTab
                .tabItem { Label("Empfänger", systemImage: "airplayvideo") }
            appearanceTab
                .tabItem { Label("Darstellung", systemImage: "ipad") }
            presentationTab
                .tabItem { Label("Präsentation", systemImage: "play.rectangle") }
        }
        .frame(width: 520)
        .padding(20)
    }

    private var receiverTab: some View {
        Form {
            TextField("Name im AirPlay-Menü", text: $settings.receiverName)
                .onSubmit { needsRestart = true }
            Picker("Max. Auflösung", selection: $settings.resolution) {
                ForEach(StreamResolution.allCases) { Text($0.title).tag($0) }
            }
            Picker("Bildrate", selection: $settings.maxFPS) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            Toggle("Ton wiedergeben", isOn: $settings.audioEnabled)
            Text("Änderungen gelten nach einem Neustart des Empfängers. Verbundene iPads werden dabei getrennt.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Empfänger neu starten") {
                receiver.restart()
                needsRestart = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(!needsRestart)
        }
        .onChange(of: settings.resolution) { needsRestart = true }
        .onChange(of: settings.maxFPS) { needsRestart = true }
        .onChange(of: settings.audioEnabled) { needsRestart = true }
        .onChange(of: settings.receiverName) { needsRestart = true }
    }

    private var appearanceTab: some View {
        Form {
            Picker("Standard-Rahmen", selection: $settings.defaultFrameStyle) {
                ForEach(FrameStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Rahmenfarbe", selection: $settings.defaultFrameColor) {
                ForEach(FrameColor.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Eigenes Rahmenbild") {
                HStack {
                    Text(settings.customFramePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Keins")
                        .foregroundStyle(.secondary)
                    Button("Wählen …") { choose { settings.customFramePath = $0 } }
                    if settings.customFramePath != nil {
                        Button("Entfernen") { settings.customFramePath = nil }
                    }
                }
            }
            Text("PNG mit transparentem Bildschirmbereich, z. B. ein iPad-Mockup. Der Bildschirm wird automatisch erkannt "
                 + "und das Bild beim Drehen des iPads mitgedreht.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Gerätenamen anzeigen", isOn: $settings.showNames)
        }
    }

    private var presentationTab: some View {
        Form {
            Picker("Hintergrund", selection: $settings.backgroundKind) {
                ForEach(BackgroundKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Farbe", selection: colorBinding(\.backgroundColor))
            if settings.backgroundKind == .gradient {
                ColorPicker("Verlauf bis", selection: colorBinding(\.gradientEndColor))
            }
            LabeledContent("Hintergrundbild") {
                HStack {
                    Text(settings.backgroundImagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Keins")
                        .foregroundStyle(.secondary)
                    Button("Wählen …") {
                        choose {
                            settings.backgroundImagePath = $0
                            settings.backgroundKind = .image
                        }
                    }
                }
            }
            Toggle("Bild füllt den ganzen Bildschirm", isOn: $settings.backgroundImageFills)
            PresentationBackground(settings: settings)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 160)
        }
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, CodableColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings[keyPath: keyPath].nsColor) },
            set: { settings[keyPath: keyPath] = CodableColor(NSColor($0)) })
    }

    private func choose(_ completion: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
