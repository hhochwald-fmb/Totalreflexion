import AppKit
import SwiftUI

/// Shared zoom state so toolbar buttons and keyboard shortcuts can drive the zoom.
@MainActor
@Observable
final class ZoomController {
    var magnification: CGFloat = 1
    @ObservationIgnored weak var scrollView: NSScrollView?

    static let range: ClosedRange<CGFloat> = 1...8

    func zoom(by factor: CGFloat) {
        guard let scrollView else { return }
        let target = min(max(scrollView.magnification * factor, Self.range.lowerBound), Self.range.upperBound)
        let center = NSPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            scrollView.animator().setMagnification(target, centeredAt: center)
        }
    }

    func reset() {
        guard let scrollView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            scrollView.animator().magnification = 1
        }
    }
}

/// Invisible buttons that give a view the zoom shortcuts ⌘+ / ⌘− / ⌘0 without a toolbar.
struct ZoomShortcuts: View {
    let zoom: ZoomController

    var body: some View {
        ZStack {
            Button("") { zoom.zoom(by: 1.4) }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { zoom.zoom(by: 1 / 1.4) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { zoom.reset() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Wraps SwiftUI content in an NSScrollView with pinch-to-zoom (trackpad), ⌥-scroll zoom and panning.
/// At zoom 1 the content exactly fills the view; zooming in renders the live video at full resolution.
struct ZoomableView<Content: View>: NSViewRepresentable {
    let controller: ZoomController
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ZoomController.range.lowerBound
        scrollView.maxMagnification = ZoomController.range.upperBound
        scrollView.contentView = CenteringClipView()
        let host = NSHostingView(rootView: AnyView(content()))
        host.sizingOptions = []
        scrollView.documentView = host
        scrollView.onMagnify = { [weak controller] value in controller?.magnification = value }
        controller.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: ZoomScrollView, context: Context) {
        (scrollView.documentView as? NSHostingView<AnyView>)?.rootView = AnyView(content())
        controller.scrollView = scrollView
    }
}

final class ZoomScrollView: NSScrollView {
    var onMagnify: (CGFloat) -> Void = { _ in }

    override func layout() {
        super.layout()
        // Content always has the size of the visible area at zoom 1.
        if let documentView, documentView.frame.size != bounds.size {
            documentView.setFrameSize(bounds.size)
        }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onMagnify(magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌥ + scroll wheel zooms around the pointer (for mice without pinch).
        if event.modifierFlags.contains(.option) {
            let factor = 1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            let point = contentView.convert(event.locationInWindow, from: nil)
            let target = min(max(magnification * factor, minMagnification), maxMagnification)
            setMagnification(target, centeredAt: point)
            onMagnify(magnification)
            return
        }
        // Without zoom there is nothing to pan; let the content react instead.
        if magnification <= 1.001 {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override var magnification: CGFloat {
        didSet { onMagnify(magnification) }
    }
}

/// Keeps the content centered while zoomed out to exactly 1.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if rect.width > documentView.frame.width {
            rect.origin.x = (documentView.frame.width - rect.width) / 2
        }
        if rect.height > documentView.frame.height {
            rect.origin.y = (documentView.frame.height - rect.height) / 2
        }
        return rect
    }
}
