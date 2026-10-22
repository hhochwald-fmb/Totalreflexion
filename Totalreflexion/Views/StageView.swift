import AppKit
import SwiftUI

/// "Bühne" view: a background that fills the screen and freely arranged devices on top.
/// Background, lock and screen are set in the control window.
struct StageView: View {
    let receiver: Receiver
    let settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController
    @State private var zoom = ZoomController()
    @State private var window: NSWindow?
    @State private var spotlightID: UUID?
    @State private var cursorTask: Task<Void, Never>?

    var body: some View {
        ZoomableView(controller: zoom) {
            PresentationCanvas(receiver: receiver, settings: settings, store: store,
                               layoutLocked: display.stageLocked, spotlightID: spotlightID) { id in
                withAnimation(.spring(duration: 0.45)) {
                    spotlightID = spotlightID == id ? nil : id
                }
            }
        }
        .ignoresSafeArea()
        .background(ZoomShortcuts(zoom: zoom))
        .background(WindowAccessor {
            window = $0
            display.outputWindow = $0
        })
        .frame(minWidth: 800, minHeight: 500)
        .onContinuousHover { phase in
            if case .active = phase {
                hideCursorWhenIdle()
            }
        }
        .onChange(of: receiver.visibleDevices.map(\.id)) { _, ids in
            // A reconnecting iPad gets a new ID; a stale spotlight would dim and lock every device.
            if let spotlightID, !ids.contains(spotlightID) {
                withAnimation(.spring(duration: 0.45)) { self.spotlightID = nil }
            }
        }
        .onExitCommand {
            if spotlightID != nil {
                withAnimation(.spring(duration: 0.45)) { spotlightID = nil }
            } else if zoom.magnification > 1 {
                zoom.reset()
            } else if let window, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    /// The pointer would sit on top of the presentation; it hides until the mouse moves again.
    private func hideCursorWhenIdle() {
        cursorTask?.cancel()
        cursorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}

private struct PresentationCanvas: View {
    let receiver: Receiver
    let settings: AppSettings
    let store: DeviceSettingsStore
    let layoutLocked: Bool
    let spotlightID: UUID?
    let toggleSpotlight: (UUID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let automatic = automaticLayout(in: size)
            ZStack(alignment: .topLeading) {
                PresentationBackground(settings: settings)
                    .frame(width: size.width, height: size.height)
                ForEach(sortedDevices) { device in
                    let appearance = DeviceAppearance(device: device, settings: settings, store: store)
                    let aspect = appearance.totalAspect(for: device)
                    let rect = placement(for: device, aspect: aspect, canvas: size, automatic: automatic)
                    PlacedDevice(device: device, appearance: appearance, store: store, rect: rect, canvas: size,
                                 aspect: aspect, showName: settings.showNames, locked: layoutLocked || spotlightID != nil,
                                 toggleSpotlight: { toggleSpotlight(device.id) })
                        .opacity(spotlightID == nil || spotlightID == device.id ? 1 : 0.15)
                        .zIndex(device.id == spotlightID ? 1000 : store[device].zIndex)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .coordinateSpace(.named(StageSpace.name))
        }
    }

    private var sortedDevices: [MirroredDevice] {
        receiver.visibleDevices
    }

    /// Grid positions for devices that have not been placed by hand yet.
    private func automaticLayout(in size: CGSize) -> [UUID: CGRect] {
        let unplaced = receiver.visibleDevices.filter { store[$0].presentationCenter == nil }
        guard !unplaced.isEmpty else { return [:] }
        let aspects = unplaced.map { DeviceAppearance(device: $0, settings: settings, store: store).totalAspect(for: $0) }
        let margin = CGSize(width: size.width * 0.08, height: size.height * 0.1)
        let bounds = CGSize(width: size.width - margin.width * 2, height: size.height - margin.height * 2)
        let frames = GridLayout.layout(aspects: aspects, in: bounds, spacing: size.width * 0.04).frames
        var result: [UUID: CGRect] = [:]
        for (device, frame) in zip(unplaced, frames) {
            result[device.id] = frame.offsetBy(dx: margin.width, dy: margin.height)
        }
        return result
    }

    private func placement(for device: MirroredDevice, aspect: CGFloat, canvas: CGSize,
                           automatic: [UUID: CGRect]) -> CGRect {
        if device.id == spotlightID {
            let maxSize = CGSize(width: canvas.width * 0.92, height: canvas.height * 0.9)
            let width = min(maxSize.width, maxSize.height * aspect)
            let height = width / aspect
            return CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
        }
        let deviceSettings = store[device]
        if let center = deviceSettings.presentationCenter, let relativeWidth = deviceSettings.presentationWidth {
            let width = relativeWidth * canvas.width
            let height = width / aspect
            return CGRect(x: center.x * canvas.width - width / 2, y: center.y * canvas.height - height / 2,
                          width: width, height: height)
        }
        return automatic[device.id] ?? CGRect(x: canvas.width * 0.3, y: canvas.height * 0.2,
                                               width: canvas.width * 0.4, height: canvas.width * 0.4 / aspect)
    }
}

/// Drags are measured on the stage, not on the device: the device moves under the pointer while dragging,
/// and its own coordinates would move with it and make it jitter.
private enum StageSpace {
    static let name = "stage"
}

/// A device on the stage that can be dragged and resized.
private struct PlacedDevice: View {
    let device: MirroredDevice
    let appearance: DeviceAppearance
    let store: DeviceSettingsStore
    let rect: CGRect
    let canvas: CGSize
    let aspect: CGFloat
    let showName: Bool
    let locked: Bool
    let toggleSpotlight: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGFloat = 0
    @State private var hovering = false

    private var currentRect: CGRect {
        let width = max(80, rect.width + resizeDelta)
        let height = width / aspect
        return CGRect(x: rect.minX + dragOffset.width, y: rect.minY + dragOffset.height, width: width, height: height)
    }

    var body: some View {
        let frame = currentRect
        DeviceView(device: device, appearance: appearance)
            .frame(width: frame.width, height: frame.height)
            .deviceChrome(device, store: store, showName: showName)
            .overlay(alignment: .bottomTrailing) {
                if hovering, !locked {
                    resizeHandle
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2, perform: toggleSpotlight)
            .gesture(moveGesture, including: locked ? .subviews : .all)
            .position(x: frame.midX, y: frame.midY)
            .animation(.spring(duration: 0.45), value: rect)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(StageSpace.name))
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { _ in
                commit()
            }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(StageSpace.name))
                    .onChanged { value in
                        // Keep the top-left corner in place while resizing.
                        let delta = max(value.translation.width, value.translation.height * aspect)
                        resizeDelta = delta
                    }
                    .onEnded { _ in commit() }
            )
            .help("Größe ändern")
    }

    private func commit() {
        let frame = currentRect
        let topZ = (store.settings.values.map(\.zIndex).max() ?? 0) + 1
        store.update(device) { settings in
            settings.presentationCenter = CGPoint(x: frame.midX / canvas.width, y: frame.midY / canvas.height)
            settings.presentationWidth = frame.width / canvas.width
            settings.zIndex = topZ
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
            resizeDelta = 0
        }
    }
}

struct PresentationBackground: View {
    let settings: AppSettings

    var body: some View {
        switch settings.backgroundKind {
        case .color:
            Color(nsColor: settings.backgroundColor.nsColor)
        case .gradient:
            LinearGradient(colors: [Color(nsColor: settings.backgroundColor.nsColor),
                                    Color(nsColor: settings.gradientEndColor.nsColor)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .image:
            if let path = settings.backgroundImagePath, let image = BackgroundImageCache.image(at: path) {
                Color.black.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: settings.backgroundImageFills ? .fill : .fit)
                }
                .clipped()
            } else {
                Color(nsColor: settings.backgroundColor.nsColor)
            }
        }
    }
}

@MainActor
enum BackgroundImageCache {
    private static var images: [String: NSImage] = [:]

    static func image(at path: String) -> NSImage? {
        if let image = images[path] {
            return image
        }
        let image = NSImage(contentsOfFile: path)
        images[path] = image
        return image
    }
}

/// Gives SwiftUI access to the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
