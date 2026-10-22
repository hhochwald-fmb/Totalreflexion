import CoreVideo
import Foundation
import IOSurface

/// Fan-out of decoded frames to every view showing a device.
/// Frames are coalesced so slow views never build up a backlog.
final class FrameSource {
    typealias Subscriber = (IOSurface, CGSize) -> Void

    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    private var deliveryScheduled = false
    private var subscribers: [UUID: Subscriber] = [:]
    private(set) var lastFrame: CVPixelBuffer?

    /// Called on the decoder thread.
    func push(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        pending = pixelBuffer
        let shouldSchedule = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.deliver()
        }
    }

    private func deliver() {
        lock.lock()
        let buffer = pending
        pending = nil
        deliveryScheduled = false
        lock.unlock()
        guard let buffer, let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        lastFrame = buffer
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        for subscriber in subscribers.values {
            subscriber(surface, size)
        }
    }

    /// Main thread only. Immediately replays the last frame so new views are never blank.
    func subscribe(_ subscriber: @escaping Subscriber) -> UUID {
        let token = UUID()
        subscribers[token] = subscriber
        if let lastFrame, let surface = CVPixelBufferGetIOSurface(lastFrame)?.takeUnretainedValue() {
            subscriber(surface, CGSize(width: CVPixelBufferGetWidth(lastFrame),
                                       height: CVPixelBufferGetHeight(lastFrame)))
        }
        return token
    }

    func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
    }
}
