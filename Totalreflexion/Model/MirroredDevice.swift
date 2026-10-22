import CoreGraphics
import Foundation
import Observation

/// One connected iPad (or iPhone) as seen by the UI.
@MainActor
@Observable
final class MirroredDevice: Identifiable {
    let id = UUID()
    /// The client's own device ID; stable across reconnects, used to remember per-device settings.
    let clientDeviceID: String
    let reportedName: String
    let model: String
    let address: String
    let frames: FrameSource

    /// Pixel size of the current video stream; changes when the iPad rotates.
    var videoSize: CGSize = .zero
    var isSuspended = false
    var hasVideo = false
    /// Hidden from all views for this session; a reconnect shows the iPad again.
    var isHidden = false
    /// Volume requested by the iPad's own volume control (0...1).
    var clientVolume: Float = 1

    @ObservationIgnored var disconnect: () -> Void = {}
    @ObservationIgnored var volumeChanged: (Float) -> Void = { _ in }

    init(clientDeviceID: String, reportedName: String, model: String, address: String, frames: FrameSource) {
        self.clientDeviceID = clientDeviceID
        self.frames = frames
        self.reportedName = reportedName
        self.model = model
        self.address = address
    }

    var isPortrait: Bool { videoSize.height > videoSize.width }

    var aspectRatio: CGFloat {
        guard videoSize.width > 0, videoSize.height > 0 else { return 4.0 / 3.0 }
        return videoSize.width / videoSize.height
    }

    var isPhone: Bool { model.lowercased().hasPrefix("iphone") }
}
