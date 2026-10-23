import AudioToolbox
import AVFoundation
import Foundation
import os

/// Decodes the mirrored AAC(-ELD) audio of one iPad and plays it.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var converter: AudioConverterRef?
    private let framesPerPacket: UInt32
    private let log = Logger(subsystem: "Totalreflexion", category: "Audio")
    private var failedDecodes = 0
    /// Where the sound is placed on the player's timeline: this RTP timestamp plays at this sample time.
    /// Following packets play right after each other from there, without gaps or overlaps.
    private var anchor: (timestamp: UInt32, sampleTime: AVAudioFramePosition)?
    private var latePackets = 0
    private var resyncs = 0

    /// Called when a packet arrived after its play time.
    var onLate: () -> Void = {}

    /// Linear gain 0...1, combines the iPad's volume slider and the local mute switch.
    var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    /// - Parameter compressionType: `ct` from SETUP: 8 = AAC-ELD (mirroring), 4 = AAC-LC.
    init?(compressionType: Int, samplesPerFrame: Int) {
        let isELD = compressionType == 8
        guard isELD || compressionType == 4 else { return nil }
        framesPerPacket = UInt32(samplesPerFrame > 0 ? samplesPerFrame : (isELD ? 480 : 1024))

        var input = AudioStreamBasicDescription(
            mSampleRate: 44100, mFormatID: isELD ? kAudioFormatMPEG4AAC_ELD : kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: framesPerPacket, mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        var output = outputFormat.streamDescription.pointee
        guard AudioConverterNew(&input, &output, &converter) == noErr, let converter else { return nil }
        // AudioSpecificConfig for 44.1 kHz stereo (ELD with 480 samples, or LC), wrapped as the decoder expects.
        var cookie = Self.elementaryStreamDescriptor(isELD ? [0xF8, 0xE8, 0x50, 0x00] : [0x12, 0x10])
        let cookieStatus = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie,
                                                     UInt32(cookie.count), &cookie)
        if cookieStatus != noErr {
            log.error("Audio magic cookie rejected: \(cookieStatus)")
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        do {
            try engine.start()
        } catch {
            log.error("Audio engine start failed: \(error.localizedDescription)")
            return nil
        }
        player.play()
        log.info("Audio output started (\(isELD ? "AAC-ELD" : "AAC-LC"), \(self.framesPerPacket) frames)")
    }

    deinit {
        stop()
    }

    func stop() {
        player.stop()
        engine.stop()
        if let converter {
            AudioConverterDispose(converter)
        }
        converter = nil
    }

    /// - Parameter playTime: host time (seconds) at which the packet should be heard.
    func enqueue(_ packet: Data, timestamp: UInt32, playTime: Double) {
        guard let converter, !packet.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesPerPacket) else { return }

        var context = DecodeContext(packet: packet)
        defer {
            context.storage?.deallocate()
            context.description.deallocate()
        }
        // The converter fills at most mDataByteSize, which follows frameLength.
        buffer.frameLength = framesPerPacket
        var frames = framesPerPacket
        let status = withUnsafeMutablePointer(to: &context) { contextPointer in
            AudioConverterFillComplexBuffer(converter, decodeInputCallback, contextPointer, &frames,
                                            buffer.mutableAudioBufferList, nil)
        }
        guard status == noErr || status == decodeInputExhausted, frames > 0 else {
            failedDecodes += 1
            if failedDecodes == 1 || failedDecodes % 1000 == 0 {
                log.error("Audio decode failed \(self.failedDecodes)x: status \(status), \(packet.count) bytes")
            }
            return
        }
        buffer.frameLength = frames
        schedule(buffer, timestamp: timestamp, playTime: playTime)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, timestamp: UInt32, playTime: Double) {
        guard let renderTime = player.lastRenderTime, renderTime.isHostTimeValid,
              let now = player.playerTime(forNodeTime: renderTime) else { return }
        let rate = outputFormat.sampleRate
        // Sound leaves the speaker `presentationLatency` after it is rendered.
        let hostOffset = playTime - engine.outputNode.presentationLatency - AVAudioTime.seconds(forHostTime: renderTime.hostTime)
        let target = now.sampleTime + AVAudioFramePosition(hostOffset * rate)

        var start = anchor.map { $0.sampleTime + AVAudioFramePosition(Int32(bitPattern: timestamp &- $0.timestamp)) }
        // The iPad's and the Mac's clocks drift apart slowly; resync once the difference becomes audible.
        if start.map({ abs($0 - target) > AVAudioFramePosition(0.025 * rate) }) ?? true {
            if anchor != nil {
                resyncs += 1
                logStatistics()
            }
            anchor = (timestamp, target)
            start = target
        }
        guard let start else { return }
        // The render thread works ahead by about one I/O buffer; a slot inside it is already gone.
        guard start > now.sampleTime + AVAudioFramePosition(0.012 * rate) else {
            latePackets += 1
            anchor = nil
            logStatistics()
            onLate()
            return
        }
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: rate))
    }

    private func logStatistics() {
        let events = latePackets + resyncs
        if events <= 10 || events % 50 == 0 {
            log.info("Audio late packets: \(self.latePackets), resyncs: \(self.resyncs)")
        }
    }
}

extension AudioPlayer {
    /// MPEG-4 ES descriptor (as in an `esds` box) around an AudioSpecificConfig: the magic cookie format
    /// AudioConverter accepts for AAC; it rejects a bare AudioSpecificConfig.
    static func elementaryStreamDescriptor(_ config: [UInt8]) -> [UInt8] {
        let specificInfo: [UInt8] = [0x05, UInt8(config.count)] + config
        // Object type 0x40 (MPEG-4 audio), stream type 0x15 (audio); buffer size and bitrates unknown.
        let decoderConfig: [UInt8] = [0x04, UInt8(13 + specificInfo.count), 0x40, 0x15]
            + [UInt8](repeating: 0, count: 11) + specificInfo
        let syncLayer: [UInt8] = [0x06, 0x01, 0x02]
        return [0x03, UInt8(3 + decoderConfig.count + syncLayer.count), 0, 0, 0] + decoderConfig + syncLayer
    }
}

private let decodeInputExhausted: OSStatus = -50_001

private struct DecodeContext {
    let packet: Data
    var consumed = false
    let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
    var storage: UnsafeMutableRawPointer?
}

private func decodeInputCallback(
    _: AudioConverterRef, packetCount: UnsafeMutablePointer<UInt32>, bufferList: UnsafeMutablePointer<AudioBufferList>,
    descriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context = userData?.assumingMemoryBound(to: DecodeContext.self) else { return -1 }
    if context.pointee.consumed {
        packetCount.pointee = 0
        return decodeInputExhausted
    }
    let packet = context.pointee.packet
    let storage = UnsafeMutableRawPointer.allocate(byteCount: packet.count, alignment: 1)
    packet.copyBytes(to: storage.assumingMemoryBound(to: UInt8.self), count: packet.count)
    // Freed by enqueue() once the converter is done with this packet.
    context.pointee.storage = storage
    context.pointee.consumed = true

    bufferList.pointee.mNumberBuffers = 1
    bufferList.pointee.mBuffers.mData = storage
    bufferList.pointee.mBuffers.mDataByteSize = UInt32(packet.count)
    bufferList.pointee.mBuffers.mNumberChannels = 2
    context.pointee.description.pointee = AudioStreamPacketDescription(
        mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
    descriptions?.pointee = context.pointee.description
    packetCount.pointee = 1
    return noErr
}
