import AppKit
import QuartzCore
import SwiftUI

/// Shows the live video of a device. Decoded IOSurfaces are handed straight to Core Animation.
struct VideoSurfaceView: NSViewRepresentable {
    let frames: FrameSource
    var fill = false

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.attach(frames)
        view.fill = fill
        return view
    }

    func updateNSView(_ view: VideoLayerView, context: Context) {
        view.attach(frames)
        view.fill = fill
    }

    static func dismantleNSView(_ view: VideoLayerView, coordinator: ()) {
        view.detach()
    }
}

final class VideoLayerView: NSView {
    private var source: FrameSource?
    private var token: UUID?

    var fill = false {
        didSet { layer?.contentsGravity = fill ? .resizeAspectFill : .resizeAspect }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ frames: FrameSource) {
        guard frames !== source else { return }
        detach()
        source = frames
        token = frames.subscribe { [weak self] surface, _ in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // The decoder recycles surfaces; re-assigning the same object would not trigger a redraw.
            if let current = self?.layer?.contents as? IOSurface, current === surface {
                self?.layer?.contents = nil
            }
            self?.layer?.contents = surface
            CATransaction.commit()
        }
    }

    func detach() {
        if let token {
            source?.unsubscribe(token)
        }
        token = nil
        source = nil
    }

    // Clicks belong to the SwiftUI gestures around the video.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
