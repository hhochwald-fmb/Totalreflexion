import AppKit
import Foundation
import Observation

enum FrameStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case modern
    case homeButton
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nur Bildschirm"
        case .modern: "iPad (randlos)"
        case .homeButton: "iPad mit Home-Button"
        case .custom: "Eigenes Rahmenbild"
        }
    }
}

enum FrameColor: String, Codable, CaseIterable, Identifiable {
    case spaceGray
    case silver
    case black
    case white
    case blue
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaceGray: "Space Grau"
        case .silver: "Silber"
        case .black: "Schwarz"
        case .white: "Weiß"
        case .blue: "Blau"
        case .pink: "Rosé"
        }
    }

    var bodyColor: NSColor {
        switch self {
        case .spaceGray: NSColor(calibratedRed: 0.36, green: 0.37, blue: 0.39, alpha: 1)
        case .silver: NSColor(calibratedRed: 0.86, green: 0.87, blue: 0.88, alpha: 1)
        case .black: NSColor(calibratedWhite: 0.1, alpha: 1)
        case .white: NSColor(calibratedWhite: 0.97, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.78, alpha: 1)
        case .pink: NSColor(calibratedRed: 0.91, green: 0.79, blue: 0.77, alpha: 1)
        }
    }

    /// Bezel around the glass: black on modern iPads, otherwise matching the body.
    var bezelColor: NSColor {
        switch self {
        case .white, .silver: NSColor(calibratedWhite: 0.98, alpha: 1)
        default: NSColor(calibratedWhite: 0.04, alpha: 1)
        }
    }
}

/// The screen the receiver reports to the iPad. Mirroring keeps the iPad's own aspect ratio, but apps with
/// their own external-display mode (e.g. presentation modes) render in this format, so 4:3 suits iPads best.
enum StreamResolution: String, CaseIterable, Identifiable {
    case iPadStandard
    case iPad
    case fullHD
    case qhd
    case uhd

    var id: String { rawValue }

    var size: (width: Int, height: Int) {
        switch self {
        case .iPadStandard: (2048, 1536)
        case .fullHD: (1920, 1080)
        case .qhd: (2560, 1440)
        case .iPad: (2732, 2048)
        case .uhd: (3840, 2160)
        }
    }

    var title: String {
        let size = size
        let name = switch self {
        case .iPadStandard: "iPad 4:3"
        case .iPad: "iPad Pro 4:3"
        case .fullHD: "Full HD 16:9"
        case .qhd: "QHD 16:9"
        case .uhd: "4K 16:9"
        }
        return "\(name) (\(size.width) × \(size.height))"
    }
}

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case color
    case gradient
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: "Farbe"
        case .gradient: "Verlauf"
        case .image: "Bild"
        }
    }
}

/// Where the iPads appear. Exactly one view is active at a time.
enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case stage
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Raster"
        case .stage: "Bühne"
        case .floating: "Frei schwebend"
        }
    }

    var explanation: String {
        switch self {
        case .grid: "Ein Fenster, alle iPads automatisch nebeneinander."
        case .stage: "Hintergrund füllt den Bildschirm, iPads frei verschieben – ideal für den Beamer."
        case .floating: "Jedes iPad als eigenes Fenster auf dem Schreibtisch, auf Wunsch über allen Apps."
        }
    }

    /// The SwiftUI window showing this view; floating devices use their own panels instead.
    var windowID: String? {
        switch self {
        case .grid: "grid"
        case .stage: "stage"
        case .floating: nil
        }
    }
}

/// App-wide settings, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var receiverName: String { didSet { defaults.set(receiverName, forKey: "receiverName") } }
    var resolution: StreamResolution { didSet { defaults.set(resolution.rawValue, forKey: "resolution") } }
    var maxFPS: Int { didSet { defaults.set(maxFPS, forKey: "maxFPS") } }
    var audioEnabled: Bool { didSet { defaults.set(audioEnabled, forKey: "audioEnabled") } }
    var showNames: Bool { didSet { defaults.set(showNames, forKey: "showNames") } }
    var defaultFrameStyle: FrameStyle { didSet { defaults.set(defaultFrameStyle.rawValue, forKey: "frameStyle") } }
    var defaultFrameColor: FrameColor { didSet { defaults.set(defaultFrameColor.rawValue, forKey: "frameColor") } }
    var customFramePath: String? { didSet { defaults.set(customFramePath, forKey: "customFramePath") } }
    var backgroundKind: BackgroundKind { didSet { defaults.set(backgroundKind.rawValue, forKey: "bgKind") } }
    var backgroundColor: CodableColor { didSet { store(backgroundColor, "bgColor") } }
    var gradientEndColor: CodableColor { didSet { store(gradientEndColor, "bgGradientEnd") } }
    var backgroundImagePath: String? { didSet { defaults.set(backgroundImagePath, forKey: "bgImage") } }
    var backgroundImageFills: Bool { didSet { defaults.set(backgroundImageFills, forKey: "bgImageFills") } }
    var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: "viewMode") } }
    var floatOnTop: Bool { didSet { defaults.set(floatOnTop, forKey: "floatOnTop") } }

    init() {
        receiverName = defaults.string(forKey: "receiverName") ?? "Totalreflexion"
        resolution = StreamResolution(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .iPadStandard
        maxFPS = defaults.object(forKey: "maxFPS") as? Int ?? 60
        audioEnabled = defaults.object(forKey: "audioEnabled") as? Bool ?? true
        showNames = defaults.object(forKey: "showNames") as? Bool ?? true
        defaultFrameStyle = FrameStyle(rawValue: defaults.string(forKey: "frameStyle") ?? "") ?? .modern
        defaultFrameColor = FrameColor(rawValue: defaults.string(forKey: "frameColor") ?? "") ?? .spaceGray
        customFramePath = defaults.string(forKey: "customFramePath")
        backgroundKind = BackgroundKind(rawValue: defaults.string(forKey: "bgKind") ?? "") ?? .gradient
        backgroundColor = Self.load("bgColor", defaults) ?? CodableColor(red: 0.08, green: 0.12, blue: 0.22)
        gradientEndColor = Self.load("bgGradientEnd", defaults) ?? CodableColor(red: 0.02, green: 0.03, blue: 0.07)
        backgroundImagePath = defaults.string(forKey: "bgImage")
        backgroundImageFills = defaults.object(forKey: "bgImageFills") as? Bool ?? true
        viewMode = ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "")
            ?? (defaults.bool(forKey: "floatingWindows") ? .floating : .grid)
        floatOnTop = defaults.object(forKey: "floatOnTop") as? Bool ?? true
    }

    private func store(_ color: CodableColor, _ key: String) {
        defaults.set(try? JSONEncoder().encode(color), forKey: key)
    }

    private static func load(_ key: String, _ defaults: UserDefaults) -> CodableColor? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(CodableColor.self, from: $0) }
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
