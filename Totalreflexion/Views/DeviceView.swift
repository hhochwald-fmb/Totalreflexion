import SwiftUI

/// Resolved look of one device: which frame, which color, which rotation.
struct DeviceAppearance: Equatable {
    var style: FrameStyle
    var color: FrameColor
    var quarterTurns: Int
    var customFramePath: String?

    @MainActor
    init(device: MirroredDevice, settings: AppSettings, store: DeviceSettingsStore) {
        let deviceSettings = store[device]
        style = deviceSettings.frameStyle ?? settings.defaultFrameStyle
        color = deviceSettings.frameColor ?? settings.defaultFrameColor
        quarterTurns = ((deviceSettings.quarterTurns % 4) + 4) % 4
        customFramePath = settings.customFramePath
        if style == .custom, customFramePath == nil {
            style = .modern
        }
        // Content much wider than any iPad comes from an app's external-display mode, not from the iPad screen;
        // an iPad frame around it would look like a device that does not exist.
        let size = device.videoSize
        if !device.isPhone, size.width > 0, size.height > 0,
           max(size.width, size.height) / min(size.width, size.height) > 1.6 {
            style = .none
        }
    }
}

/// Geometry of a drawn device: screen size plus bezel insets, in arbitrary units.
struct DeviceGeometry {
    var screen: CGSize
    var insets: EdgeInsets
    var screenCornerRadius: CGFloat
    var outerCornerRadius: CGFloat

    var total: CGSize {
        CGSize(width: screen.width + insets.leading + insets.trailing,
               height: screen.height + insets.top + insets.bottom)
    }

    var aspectRatio: CGFloat { total.width / max(total.height, 1) }

    static func make(screenAspect: CGFloat, style: FrameStyle, isPhone: Bool) -> DeviceGeometry {
        // Short side of the screen = 1000 units.
        let screen = screenAspect >= 1
            ? CGSize(width: 1000 * screenAspect, height: 1000)
            : CGSize(width: 1000, height: 1000 / screenAspect)
        let landscape = screen.width >= screen.height
        switch style {
        case .none, .custom:
            return DeviceGeometry(screen: screen, insets: EdgeInsets(), screenCornerRadius: 0, outerCornerRadius: 0)
        case .modern:
            let bezel: CGFloat = isPhone ? 40 : 62
            let insets = EdgeInsets(top: bezel, leading: bezel, bottom: bezel, trailing: bezel)
            return DeviceGeometry(screen: screen, insets: insets, screenCornerRadius: isPhone ? 110 : 45,
                                  outerCornerRadius: isPhone ? 150 : 107)
        case .homeButton:
            let side: CGFloat = 70
            let chin: CGFloat = isPhone ? 230 : 175
            let insets = landscape
                ? EdgeInsets(top: side, leading: chin, bottom: side, trailing: chin)
                : EdgeInsets(top: chin, leading: side, bottom: chin, trailing: side)
            return DeviceGeometry(screen: screen, insets: insets, screenCornerRadius: 4, outerCornerRadius: 120)
        }
    }
}

/// One device with live video and the chosen frame. Sizes itself to its natural aspect ratio.
struct DeviceView: View {
    let device: MirroredDevice
    let appearance: DeviceAppearance

    private var rotatedScreenAspect: CGFloat {
        let aspect = device.aspectRatio
        return appearance.quarterTurns % 2 == 1 ? 1 / aspect : aspect
    }

    var body: some View {
        if appearance.style == .custom, let path = appearance.customFramePath,
           let frame = CustomFrame.load(path: path) {
            CustomFramedDevice(device: device, frame: frame, quarterTurns: appearance.quarterTurns,
                               screenIsPortrait: rotatedScreenAspect < 1)
        } else {
            let geometry = DeviceGeometry.make(screenAspect: rotatedScreenAspect, style: appearance.style,
                                               isPhone: device.isPhone)
            DrawnFrameDevice(device: device, geometry: geometry, appearance: appearance)
                .aspectRatio(geometry.aspectRatio, contentMode: .fit)
        }
    }
}

/// Screen rotated by a number of quarter turns, filling the proposed size.
struct RotatedVideo: View {
    let device: MirroredDevice
    let quarterTurns: Int
    var fill = false

    var body: some View {
        GeometryReader { proxy in
            let swap = quarterTurns % 2 == 1
            let size = swap ? CGSize(width: proxy.size.height, height: proxy.size.width) : proxy.size
            VideoSurfaceView(frames: device.frames, fill: fill)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(Double(quarterTurns) * 90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct DrawnFrameDevice: View {
    let device: MirroredDevice
    let geometry: DeviceGeometry
    let appearance: DeviceAppearance

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / geometry.total.width
            let insets = geometry.insets
            ZStack(alignment: .topLeading) {
                if appearance.style != .none {
                    chassis(scale: scale)
                }
                RotatedVideo(device: device, quarterTurns: appearance.quarterTurns)
                    .frame(width: geometry.screen.width * scale, height: geometry.screen.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: geometry.screenCornerRadius * scale,
                                                style: .continuous))
                    .offset(x: insets.leading * scale, y: insets.top * scale)
                if appearance.style == .homeButton {
                    homeButton(scale: scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func chassis(scale: CGFloat) -> some View {
        let outer = RoundedRectangle(cornerRadius: geometry.outerCornerRadius * scale, style: .continuous)
        let edge = 9 * scale
        return ZStack {
            outer.fill(
                LinearGradient(colors: [Color(nsColor: appearance.color.bodyColor).opacity(0.85),
                                        Color(nsColor: appearance.color.bodyColor)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: max(0, geometry.outerCornerRadius * scale - edge), style: .continuous)
                .fill(Color(nsColor: appearance.style == .homeButton ? frontColor : appearance.color.bezelColor))
                .padding(edge)
            if appearance.style == .modern {
                camera(scale: scale)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 30 * scale, y: 12 * scale)
    }

    private var frontColor: NSColor {
        switch appearance.color {
        case .silver, .white, .pink: NSColor(calibratedWhite: 0.97, alpha: 1)
        default: NSColor(calibratedWhite: 0.06, alpha: 1)
        }
    }

    private func camera(scale: CGFloat) -> some View {
        let total = geometry.total
        let size = 14 * scale
        // Modern iPads carry the camera on the long edge; shown on the top bezel.
        return Circle()
            .fill(Color(white: 0.18))
            .overlay(Circle().fill(Color(red: 0.15, green: 0.2, blue: 0.35).opacity(0.6)).padding(size * 0.3))
            .frame(width: size, height: size)
            .position(x: total.width * scale / 2, y: geometry.insets.top * scale / 2)
    }

    private func homeButton(scale: CGFloat) -> some View {
        let total = geometry.total
        let insets = geometry.insets
        let landscape = insets.leading > insets.top
        let diameter = (landscape ? insets.trailing : insets.bottom) * 0.55 * scale
        let center = landscape
            ? CGPoint(x: (total.width - insets.trailing / 2) * scale, y: total.height * scale / 2)
            : CGPoint(x: total.width * scale / 2, y: (total.height - insets.bottom / 2) * scale)
        return Circle()
            .strokeBorder(Color.gray.opacity(0.55), lineWidth: max(1, 4 * scale))
            .frame(width: diameter, height: diameter)
            .position(center)
    }
}

private struct CustomFramedDevice: View {
    let device: MirroredDevice
    let frame: CustomFrame
    let quarterTurns: Int
    let screenIsPortrait: Bool

    /// Rotate the frame image when the device is held the other way round than the image was drawn.
    private var rotateImage: Bool { frame.isPortrait != screenIsPortrait }

    var body: some View {
        let imageAspect = frame.pixelSize.width / frame.pixelSize.height
        let aspect = rotateImage ? 1 / imageAspect : imageAspect
        GeometryReader { proxy in
            let size = proxy.size
            let rect = screenRect(in: size)
            ZStack(alignment: .topLeading) {
                RotatedVideo(device: device, quarterTurns: quarterTurns, fill: true)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                Image(nsImage: frame.image)
                    .resizable()
                    .frame(width: rotateImage ? size.height : size.width,
                           height: rotateImage ? size.width : size.height)
                    .rotationEffect(.degrees(rotateImage ? 90 : 0))
                    .position(x: size.width / 2, y: size.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    private func screenRect(in size: CGSize) -> CGRect {
        let unit = frame.screenRect
        // Rotating the image 90° clockwise maps (x, y) to (1 - y - h, x).
        let rotated = rotateImage
            ? CGRect(x: 1 - unit.minY - unit.height, y: unit.minX, width: unit.height, height: unit.width)
            : unit
        return CGRect(x: rotated.minX * size.width, y: rotated.minY * size.height,
                      width: rotated.width * size.width, height: rotated.height * size.height)
    }
}

extension DeviceAppearance {
    /// Width/height of the device including its frame, used for layout.
    @MainActor
    func totalAspect(for device: MirroredDevice) -> CGFloat {
        let aspect = quarterTurns % 2 == 1 ? 1 / device.aspectRatio : device.aspectRatio
        if style == .custom, let path = customFramePath, let frame = CustomFrame.load(path: path) {
            let imageAspect = frame.pixelSize.width / frame.pixelSize.height
            return frame.isPortrait != (aspect < 1) ? 1 / imageAspect : imageAspect
        }
        return DeviceGeometry.make(screenAspect: aspect, style: style, isPhone: device.isPhone).aspectRatio
    }
}
