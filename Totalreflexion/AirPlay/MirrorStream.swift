import Foundation

/// Parses the AirPlay screen-mirroring TCP stream: 128-byte header + payload per packet.
/// Video payloads are AES-CTR encrypted, length-prefixed (AVCC) H.264 NAL units.
final class MirrorStreamParser {
    enum Event {
        case parameterSets(sps: Data, pps: Data)
        /// An encoded frame and its iPad timestamp in seconds (the clock of the audio sync packets).
        case frame(Data, timestamp: Double)
        case suspended(Bool)
    }

    private var buffer = Data()
    private let cipher: AESCTR
    private var isSuspended = false
    private let onEvent: (Event) -> Void

    init(sessionKey: Data, streamConnectionID: UInt64, onEvent: @escaping (Event) -> Void) {
        let key = Crypto.sha512(Data("AirPlayStreamKey\(streamConnectionID)".utf8), sessionKey).prefix(16)
        let iv = Crypto.sha512(Data("AirPlayStreamIV\(streamConnectionID)".utf8), sessionKey).prefix(16)
        cipher = AESCTR(key: Data(key), iv: Data(iv))
        self.onEvent = onEvent
    }

    func append(_ data: Data) {
        buffer.append(data)
        while buffer.count >= 128 {
            let header = [UInt8](buffer.prefix(128))
            let payloadSize = Int(UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16
                | UInt32(header[3]) << 24)
            guard buffer.count >= 128 + payloadSize else { return }
            let start = buffer.startIndex + 128
            let payload = Data(buffer[start..<(start + payloadSize)])
            buffer.removeSubrange(buffer.startIndex..<(start + payloadSize))
            handle(header: header, payload: payload)
        }
    }

    private func handle(header: [UInt8], payload: Data) {
        switch header[4] {
        case 0x00:
            let decrypted = cipher.process(payload)
            if Self.isValidAVCC(decrypted) {
                onEvent(.frame(decrypted, timestamp: Self.timestamp(header)))
            }
        case 0x01:
            // 0x56 / 0x5e in byte 6: the iPad went to sleep or locked its screen.
            let suspended = header[6] == 0x56 || header[6] == 0x5E
            if suspended != isSuspended {
                isSuspended = suspended
                onEvent(.suspended(suspended))
            }
            if let sets = Self.parseAVCDecoderConfiguration(payload) {
                onEvent(.parameterSets(sps: sets.sps, pps: sets.pps))
            }
        default:
            // 0x02 heartbeat, 0x05 streaming report: nothing to do.
            break
        }
    }

    /// NTP format at bytes 8-15, little-endian: seconds in the upper half, fraction in the lower.
    private static func timestamp(_ header: [UInt8]) -> Double {
        let raw = header[8..<16].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Double(raw >> 32) + Double(raw & 0xFFFF_FFFF) / 4_294_967_296
    }

    /// avcC layout: version, profile, compat, level, 0xFF, 0xE1, spsLen(2), sps, numPPS, ppsLen(2), pps.
    private static func parseAVCDecoderConfiguration(_ data: Data) -> (sps: Data, pps: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count > 8 else { return nil }
        let spsLength = Int(bytes[6]) << 8 | Int(bytes[7])
        let ppsLengthOffset = 8 + spsLength + 1
        guard bytes.count >= ppsLengthOffset + 2 else { return nil }
        let ppsLength = Int(bytes[ppsLengthOffset]) << 8 | Int(bytes[ppsLengthOffset + 1])
        let ppsStart = ppsLengthOffset + 2
        guard spsLength > 0, ppsLength > 0, bytes.count >= ppsStart + ppsLength else { return nil }
        return (Data(bytes[8..<(8 + spsLength)]), Data(bytes[ppsStart..<(ppsStart + ppsLength)]))
    }

    /// A wrong key produces garbage lengths, so validate before handing data to the decoder.
    private static func isValidAVCC(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            while offset + 4 <= bytes.count {
                let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                    | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                offset += 4
                guard length > 0, offset + length <= bytes.count, bytes[offset] & 0x80 == 0 else { return false }
                offset += length
            }
            return offset == bytes.count && offset > 0
        }
    }
}
