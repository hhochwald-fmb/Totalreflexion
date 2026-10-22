import AppKit
import Observation
import SwiftUI

/// Shows iPads in their own borderless windows ("Frei schwebend", like AirServer), puts a single iPad
/// full screen on request in any view, and moves the grid or stage window between screens.
@MainActor
@Observable
final class DisplayController {
    /// Device currently shown full screen; nil = none.
    private(set) var fullScreenID: UUID?
    /// Stage only: devices cannot be moved or resized.
    var stageLocked = false
    @ObservationIgnored var didHandleLaunch = false
    /// The grid or stage window, whichever is open.
    @ObservationIgnored weak var outputWindow: NSWindow?
    @ObservationIgnored private var fullScreenScreen: NSScreen?
    @ObservationIgnored private var panels: [UUID: DevicePanel] = [:]
    @ObservationIgnored private let codeOverlay = CodeOverlay()
    @ObservationIgnored private let receiver: Receiver
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let store: DeviceSettingsStore

    init(receiver: Receiver, settings: AppSettings, store: DeviceSettingsStore) {
        self.receiver = receiver
        self.settings = settings
        self.store = store
    }

    func start() {
        observe()
    }

    func setHidden(_ device: MirroredDevice, _ hidden: Bool) {
        device.isHidden = hidden
        if hidden, fullScreenID == device.id {
            fullScreenID = nil
        }
    }

    /// Without a screen: toggles full screen on the screen the device is on. With a screen: moves it there.
    func toggleFullScreen(_ device: MirroredDevice, on screen: NSScreen? = nil) {
        if fullScreenID == device.id, screen == nil {
            fullScreenID = nil
            fullScreenScreen = nil
        } else {
            fullScreenScreen = screen
            fullScreenID = device.id
        }
    }

    /// Tiles all device windows on the main screen.
    func arrange() {
        let devices = receiver.visibleDevices.filter { panels[$0.id] != nil && $0.id != fullScreenID }
        guard let screen = NSScreen.main, !devices.isEmpty else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let bounds = CGSize(width: visible.width - margin * 2, height: visible.height - margin * 2)
        let aspects = devices.compactMap { panels[$0.id]?.aspect }
        let frames = GridLayout.layout(aspects: aspects, in: bounds, spacing: 24).frames
        for (device, rect) in zip(devices, frames) {
            // GridLayout counts from the top, screen coordinates from the bottom.
            let frame = NSRect(x: visible.minX + margin + rect.minX, y: visible.maxY - margin - rect.maxY,
                               width: rect.width, height: rect.height)
            panels[device.id]?.setFrame(frame, display: true, animate: true)
            store.update(device) { $0.floatingFrame = frame }
        }
    }

    // MARK: - Grid or stage window

    func toggleOutputFullScreen() {
        outputWindow?.makeKeyAndOrderFront(nil)
        outputWindow?.toggleFullScreen(nil)
    }

    /// Moves the grid or stage window to a screen and makes it full screen there.
    func moveOutput(to screen: NSScreen) {
        guard let window = outputWindow else { return }
        let wasFullScreen = window.styleMask.contains(.fullScreen)
        if wasFullScreen {
            window.toggleFullScreen(nil)
        }
        // Leaving full screen is animated; moving during the animation is ignored.
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasFullScreen ? 0.8 : 0)) {
            window.setFrame(screen.visibleFrame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }
    }

    // MARK: - Keeping the windows in sync

    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync() {
        codeOverlay.show(receiver.pairingCode)
        let visible = receiver.visibleDevices
        let wanted = visible.filter { settings.viewMode == .floating || $0.id == fullScreenID }
        let wantedIDs = Set(wanted.map(\.id))
        for (id, panel) in panels where !wantedIDs.contains(id) {
            panel.close()
            panel.contentView = nil
            panels[id] = nil
        }
        let level: NSWindow.Level = settings.floatOnTop ? .floating : .normal
        for (index, device) in wanted.enumerated() {
            let aspect = DeviceAppearance(device: device, settings: settings, store: store).totalAspect(for: device)
            let panel = panels[device.id] ?? makePanel(for: device, aspect: aspect, index: index)
            let fullScreen = device.id == fullScreenID ? (fullScreenScreen ?? panel.screen ?? NSScreen.main) : nil
            panel.update(aspect: aspect, fullScreenOn: fullScreen, level: level)
        }
    }

    private func makePanel(for device: MirroredDevice, aspect: CGFloat, index: Int) -> DevicePanel {
        let panel = DevicePanel(contentRect: initialFrame(for: device, aspect: aspect, index: index))
        panel.aspect = aspect
        let host = NSHostingView(rootView: FloatingDeviceView(device: device, settings: settings, store: store,
                                                              display: self, actions: PanelActions(panel: panel)))
        // The window decides the size, not the SwiftUI content.
        host.sizingOptions = []
        panel.contentView = host
        let id = device.id
        panel.onFrameChange = { [weak self, weak device] frame in
            guard let self, let device else { return }
            store.update(device) { $0.floatingFrame = frame }
        }
        panel.onEscape = { [weak self] in
            if self?.fullScreenID == id {
                self?.fullScreenID = nil
            }
        }
        panel.orderFront(nil)
        panels[id] = panel
        return panel
    }

    private func initialFrame(for device: MirroredDevice, aspect: CGFloat, index: Int) -> NSRect {
        if let saved = store[device].floatingFrame,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            return DevicePanel.fitted(saved, aspect: aspect)
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let width = min(visible.height * 0.45 * aspect, visible.width * 0.45)
        let height = width / aspect
        let offset = CGFloat(index) * 40
        return NSRect(x: visible.minX + 60 + offset, y: visible.maxY - 60 - height - offset,
                      width: width, height: height)
    }
}

extension NSWindow.Level {
    /// Above the menu bar, so a full-screen device covers the whole display.
    static let fullScreenDevice = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
}

/// Borderless, transparent window holding one device. Moved and resized with the mouse.
final class DevicePanel: NSPanel, NSWindowDelegate {
    var aspect: CGFloat = 1
    private(set) var isFullScreen = false
    var onFrameChange: (NSRect) -> Void = { _ in }
    var onEscape: () -> Void = {}
    private var normalFrame: NSRect?
    private var tracking: (mouse: NSPoint, frame: NSRect)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 120, height: 120)
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    func update(aspect newAspect: CGFloat, fullScreenOn screen: NSScreen?, level newLevel: NSWindow.Level) {
        aspect = newAspect
        if let screen {
            if !isFullScreen {
                normalFrame = frame
                isFullScreen = true
                // Clears the aspect-ratio constraint.
                resizeIncrements = NSSize(width: 1, height: 1)
                makeKeyAndOrderFront(nil)
            }
            level = .fullScreenDevice
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if frame != screen.frame {
                setFrame(screen.frame, display: true)
            }
            return
        }
        if isFullScreen {
            isFullScreen = false
            if let normalFrame {
                setFrame(normalFrame, display: true)
            }
        }
        level = newLevel
        // Floating windows follow the user into other Spaces and over full-screen apps such as PowerPoint.
        collectionBehavior = newLevel == .normal ? [.managed] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = NSSize(width: newAspect, height: 1)
        if abs(frame.width / max(frame.height, 1) - newAspect) > 0.01 {
            // The iPad was rotated or got another frame.
            setFrame(Self.fitted(frame, aspect: newAspect), display: true)
        }
    }

    /// Same center and area, new aspect ratio.
    static func fitted(_ frame: NSRect, aspect: CGFloat) -> NSRect {
        let width = (frame.width * frame.height * aspect).squareRoot()
        let height = width / aspect
        return NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    // MARK: - Mouse tracking (screen coordinates, since the window moves under the pointer)

    func dragWindow() {
        let start = beginTracking()
        let mouse = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: start.frame.minX + mouse.x - start.mouse.x,
                               y: start.frame.minY + mouse.y - start.mouse.y))
    }

    /// Resizes from the bottom-right corner, keeping the top-left corner in place.
    func resizeWindow() {
        let start = beginTracking()
        let mouse = NSEvent.mouseLocation
        let grow = max(mouse.x - start.mouse.x, (start.mouse.y - mouse.y) * aspect)
        let width = max(minSize.width, start.frame.width + grow)
        let height = width / aspect
        setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height),
                 display: true)
    }

    func endTracking() {
        guard tracking != nil else { return }
        tracking = nil
        if !isFullScreen {
            onFrameChange(frame)
        }
    }

    private func beginTracking() -> (mouse: NSPoint, frame: NSRect) {
        if let tracking {
            return tracking
        }
        let start = (mouse: NSEvent.mouseLocation, frame: frame)
        tracking = start
        return start
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if !isFullScreen {
            onFrameChange(frame)
        }
    }
}

/// Window operations triggered from SwiftUI; holds the panel weakly to avoid a retain cycle.
struct PanelActions {
    weak var panel: DevicePanel?

    @MainActor func drag() { panel?.dragWindow() }
    @MainActor func resize() { panel?.resizeWindow() }
    @MainActor func endTracking() { panel?.endTracking() }
}

/// Content of a device window: the device with its frame, or alone on black when full screen.
struct FloatingDeviceView: View {
    let device: MirroredDevice
    let settings: AppSettings
    let store: DeviceSettingsStore
    let display: DisplayController
    let actions: PanelActions
    @State private var hovering = false

    var body: some View {
        let fullScreen = display.fullScreenID == device.id
        ZStack {
            if fullScreen {
                Color.black
            }
            DeviceView(device: device, appearance: DeviceAppearance(device: device, settings: settings, store: store))
                .deviceChrome(device, store: store, showName: false)
                .padding(fullScreen ? 20 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering, !fullScreen {
                resizeHandle
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { display.toggleFullScreen(device) }
        .gesture(moveGesture, including: fullScreen ? .subviews : .all)
        .ignoresSafeArea()
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in actions.drag() }
            .onEnded { _ in actions.endTracking() }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in actions.resize() }
                    .onEnded { _ in actions.endTracking() }
            )
            .help("Größe ändern")
    }
}
