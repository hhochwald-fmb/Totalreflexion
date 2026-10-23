import Foundation

/// Sends NTP-style timing requests to the iPad, as an Apple TV does while mirroring.
final class TimingClient {
    private let socket: UDPSocket?
    private let timer: DispatchSourceTimer
    let localPort: UInt16

    init(queue: DispatchQueue, remote: RemoteAddress) {
        let socket = UDPSocket(queue: queue) { _ in
            // Replies are not needed: frames are shown as soon as they are decoded.
        }
        self.socket = socket
        localPort = socket?.port ?? 0
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 3)
        timer.setEventHandler {
            socket?.send(Self.request(), to: remote)
        }
        timer.resume()
    }

    func close() {
        timer.cancel()
        socket?.close()
    }

    private static func request() -> Data {
        var packet = [UInt8](repeating: 0, count: 32)
        packet[0] = 0x80
        packet[1] = 0xD2
        packet[3] = 0x07
        let now = Date().timeIntervalSince1970 + 2_208_988_800
        let seconds = UInt32(now)
        let fraction = UInt32((now - floor(now)) * 4_294_967_296)
        for index in 0..<4 {
            packet[24 + index] = UInt8(truncatingIfNeeded: seconds >> (24 - 8 * index))
            packet[28 + index] = UInt8(truncatingIfNeeded: fraction >> (24 - 8 * index))
        }
        return Data(packet)
    }
}

/// Receives the RTP audio stream (type 96), decrypts it (AES-CBC per packet) and plays it at its timestamp.
final class AudioReceiver {
    private var dataSocket: UDPSocket?
    private var controlSocket: UDPSocket?
    private let player: AudioPlayer?
    private let clock: PlayoutClock
    private let key: Data
    private let iv: Data
    private var lastSequence: UInt16?
    /// From the latest sync packet: this RTP timestamp belongs to this iPad time (seconds, the clock of the
    /// video timestamps).
    private var sync: (timestamp: UInt32, time: Double)?

    var dataPort: UInt16 { dataSocket?.port ?? 0 }
    var controlPort: UInt16 { controlSocket?.port ?? 0 }

    var clientVolume: Float = 1 { didSet { applyVolume() } }
    var localVolume: Float = 1 { didSet { applyVolume() } }

    init?(queue: DispatchQueue, key: Data, iv: Data, compressionType: Int, samplesPerFrame: Int, clock: PlayoutClock) {
        self.key = key
        self.iv = iv
        self.clock = clock
        player = AudioPlayer(compressionType: compressionType, samplesPerFrame: samplesPerFrame)
        player?.onLate = { clock.reportLate() }
        dataSocket = UDPSocket(queue: queue) { [weak self] packet in
            self?.handle(packet)
        }
        controlSocket = UDPSocket(queue: queue) { [weak self] packet in
            self?.handleControl(packet)
        }
        guard dataSocket != nil, controlSocket != nil else { return nil }
    }

    func stop() {
        dataSocket?.close()
        controlSocket?.close()
        dataSocket = nil
        controlSocket = nil
        player?.stop()
    }

    private func applyVolume() {
        player?.volume = clientVolume * localVolume
    }

    private func handleControl(_ packet: Data) {
        let bytes = [UInt8](packet)
        guard bytes.count > 4 else { return }
        switch bytes[1] & 0x7F {
        case 0x54 where bytes.count >= 20:
            // Sync: NTP time (since 1900) at bytes 8-15 belongs to the RTP timestamp at bytes 16-19.
            let seconds = Self.uint32(bytes, at: 8)
            let fraction = Self.uint32(bytes, at: 12)
            let time = Double(seconds) - 2_208_988_800 + Double(fraction) / 4_294_967_296
            sync = (Self.uint32(bytes, at: 16), time)
        case 0x56:
            // Retransmission with an embedded RTP packet.
            handle(packet.dropFirst(4))
        default:
            break
        }
    }

    private func handle(_ packet: Data) {
        let bytes = [UInt8](packet)
        guard bytes.count > 12, bytes[1] & 0x7F == 0x60 else { return }
        let sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        if let lastSequence, Int16(bitPattern: sequence &- lastSequence) <= 0 {
            return
        }
        lastSequence = sequence
        // Without a sync packet (the first second) the sound cannot be placed next to the picture yet.
        guard let sync else { return }
        let timestamp = Self.uint32(bytes, at: 4)
        let remoteTime = sync.time + Double(Int32(bitPattern: timestamp &- sync.timestamp)) / 44100
        clock.observe(remoteTime)
        guard let pictureTime = clock.playTime(for: remoteTime) else { return }
        let playTime = pictureTime + PlayoutClock.pictureLatency

        let payload = Data(bytes[12...])
        let encryptedLength = payload.count / 16 * 16
        var decrypted = Crypto.aesCBCDecrypt(key: key, iv: iv, data: payload.prefix(encryptedLength))
        decrypted.append(payload.suffix(from: encryptedLength))
        player?.enqueue(decrypted, timestamp: timestamp, playTime: playTime)
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
