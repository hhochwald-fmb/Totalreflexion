import Foundation
import os

/// Host time in seconds on the mach clock, the timeline shared by Dispatch and Core Audio.
enum HostClock {
    static var now: Double { seconds(DispatchTime.now()) }

    static func seconds(_ time: DispatchTime) -> Double {
        Double(time.uptimeNanoseconds) / 1_000_000_000
    }

    static func dispatchTime(_ seconds: Double) -> DispatchTime {
        DispatchTime(uptimeNanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Maps the iPad's media timestamps to local play times; shared by the audio and video of one session.
///
/// Wi-Fi delivers packets in bursts with pauses of up to a quarter second. Playing every picture and sound at
/// its timestamp plus a fixed delay bridges those pauses and keeps picture and sound in sync, as an Apple TV does.
final class PlayoutClock: @unchecked Sendable {
    private let lock = NSLock()
    /// Smallest arrival-minus-timestamp per second of arrival: the clock difference plus the network's best case.
    private var minimumOffsets: [(second: Int, offset: Double)] = []
    private var offset: Double?
    private var delay = PlayoutClock.initialDelay
    private var lastRaise = 0.0
    private let log = Logger(subsystem: "Totalreflexion", category: "Playout")

    private static let initialDelay = 0.2
    private static let maximumDelay = 0.5
    /// Seconds of arrivals the offset is estimated from; long enough to contain a burst's first packet,
    /// short enough to follow the iPad's clock drifting against the Mac's.
    private static let window = 5

    /// Records the arrival of a packet with the given iPad timestamp (seconds).
    func observe(_ remoteTime: Double, arrival: Double = HostClock.now) {
        let sample = arrival - remoteTime
        let second = Int(arrival)
        locked {
            if let last = minimumOffsets.last, last.second == second {
                minimumOffsets[minimumOffsets.count - 1].offset = min(last.offset, sample)
            } else {
                minimumOffsets.append((second, sample))
                minimumOffsets.removeAll { second - $0.second >= Self.window }
            }
            let estimate = minimumOffsets.map(\.offset).min() ?? sample
            // Small changes are noise; following them would make the picture judder and the sound resync.
            if offset.map({ abs($0 - estimate) > 0.01 }) ?? true {
                offset = estimate
            }
        }
    }

    /// Host time at which the picture or sound with this iPad timestamp should be seen or heard.
    func playTime(for remoteTime: Double) -> Double? {
        locked { offset.map { remoteTime + $0 + delay } }
    }

    /// Something arrived too late to be played on time: wait a little longer from now on.
    func reportLate() {
        let now = HostClock.now
        let raised: Double? = locked {
            guard now - lastRaise > 2, delay < Self.maximumDelay else { return nil }
            lastRaise = now
            delay = min(delay + 0.04, Self.maximumDelay)
            return delay
        }
        if let raised {
            log.info("Playout delay raised to \(raised, format: .fixed(precision: 2)) s")
        }
    }

    var currentDelay: Double { locked { delay } }

    /// From decoding a frame until it is on screen: decoding, drawing, the next display refresh and the display's
    /// own processing. Sound has no such way to go, so it waits this long to match the picture.
    static let pictureLatency = 0.09

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Runs work items in order on a queue, each not before its host time. Used to hold back video frames
/// (still compressed, so waiting costs little memory) until their play time.
final class PlayoutQueue {
    private let timer: DispatchSourceTimer
    private var items: [(time: Double, work: () -> Void)] = []
    private var lastTime = 0.0

    /// Never hold anything back longer than this, whatever a timestamp says.
    private static let maximumWait = 1.0

    init(queue: DispatchQueue) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.runDueItems() }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    /// Must be called on the queue. Items keep their order, so a later item never runs before an earlier one.
    func enqueue(at time: Double, _ work: @escaping () -> Void) {
        let time = max(min(time, HostClock.now + Self.maximumWait), lastTime)
        lastTime = time
        items.append((time, work))
        if items.count == 1 {
            arm()
        }
    }

    /// Runs `work` right after everything already waiting, or at once if nothing is.
    func enqueueAfterPending(_ work: @escaping () -> Void) {
        if items.isEmpty {
            work()
        } else {
            enqueue(at: lastTime, work)
        }
    }

    /// Drops everything still waiting, e.g. when mirroring stops.
    func removeAll() {
        items.removeAll()
        lastTime = 0
    }

    private func arm() {
        guard let first = items.first else { return }
        timer.schedule(deadline: HostClock.dispatchTime(first.time), leeway: .milliseconds(1))
    }

    private func runDueItems() {
        let now = HostClock.now
        while let first = items.first, first.time <= now + 0.001 {
            items.removeFirst()
            first.work()
        }
        arm()
    }
}
