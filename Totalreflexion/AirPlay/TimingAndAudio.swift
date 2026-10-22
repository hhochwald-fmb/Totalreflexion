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

/// Receives the RTP audio stream (type 96), decrypts it (AES-CBC per packet) and plays it.
final class AudioReceiver {
    private var dataSocket: UDPSocket?
    private var controlSocket: UDPSocket?
    private let player: AudioPlayer?
    private let key: Data
    private let iv: Data
    private var lastSequence: UInt16?

    var dataPort: UInt16 { dataSocket?.port ?? 0 }
    var controlPort: UInt16 { controlSocket?.port ?? 0 }

    var clientVolume: Float = 1 { didSet { applyVolume() } }
    var localVolume: Float = 1 { didSet { applyVolume() } }

    init?(queue: DispatchQueue, key: Data, iv: Data, compressionType: Int, samplesPerFrame: Int) {
        self.key = key
        self.iv = iv
        player = AudioPlayer(compressionType: compressionType, samplesPerFrame: samplesPerFrame)
        dataSocket = UDPSocket(queue: queue) { [weak self] packet in
            self?.handle(packet)
        }
        // The control port carries retransmissions (0xD6 with an embedded RTP packet).
        controlSocket = UDPSocket(queue: queue) { [weak self] packet in
            guard packet.count > 4, packet[packet.startIndex + 1] & 0x7F == 0x56 else { return }
            self?.handle(packet.dropFirst(4))
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

    private func handle(_ packet: Data) {
        let bytes = [UInt8](packet)
        guard bytes.count > 12, bytes[1] & 0x7F == 0x60 else { return }
        let sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        if let lastSequence, Int16(bitPattern: sequence &- lastSequence) <= 0 {
            return
        }
        lastSequence = sequence

        let payload = Data(bytes[12...])
        let encryptedLength = payload.count / 16 * 16
        var decrypted = Crypto.aesCBCDecrypt(key: key, iv: iv, data: payload.prefix(encryptedLength))
        decrypted.append(payload.suffix(from: encryptedLength))
        player?.enqueue(decrypted)
    }
}
