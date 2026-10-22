import CoreGraphics
import Foundation
import Observation

/// Settings remembered per iPad (keyed by the iPad's device ID), so a device that reconnects
/// lands at the same place with the same frame.
struct DeviceSettings: Codable, Equatable {
    var alias: String?
    /// nil = use the app-wide default.
    var frameStyle: FrameStyle?
    var frameColor: FrameColor?
    /// Extra rotation in quarter turns, for iPads mounted on a stand.
    var quarterTurns = 0
    var muted = false
    /// Presentation layout in canvas-relative coordinates (0...1); nil = not placed yet.
    var presentationCenter: CGPoint?
    /// Width of the device including frame, relative to the canvas width.
    var presentationWidth: CGFloat?
    var zIndex: Double = 0
    /// Screen frame of the device's own window ("Eigene Fenster" mode); nil = not placed yet.
    var floatingFrame: CGRect?
}

@MainActor
@Observable
final class DeviceSettingsStore {
    private(set) var settings: [String: DeviceSettings]
    private let key = "deviceSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([String: DeviceSettings].self, from: data) {
            settings = stored
        } else {
            settings = [:]
        }
    }

    subscript(device: MirroredDevice) -> DeviceSettings {
        get { settings[device.clientDeviceID] ?? DeviceSettings() }
        set {
            settings[device.clientDeviceID] = newValue
            persist()
        }
    }

    func update(_ device: MirroredDevice, _ change: (inout DeviceSettings) -> Void) {
        var value = self[device]
        change(&value)
        self[device] = value
    }

    func displayName(_ device: MirroredDevice) -> String {
        self[device].alias ?? device.reportedName
    }

    func resetLayout() {
        for key in settings.keys {
            settings[key]?.presentationCenter = nil
            settings[key]?.presentationWidth = nil
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}
