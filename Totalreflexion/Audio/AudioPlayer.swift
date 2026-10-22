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
    private var queuedBuffers = 0
    private let lock = NSLock()

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
        // AudioSpecificConfig for 44.1 kHz stereo (ELD with 480 samples, or LC).
        var cookie: [UInt8] = isELD ? [0xF8, 0xE8, 0x50, 0x00] : [0x12, 0x10]
        AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), &cookie)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        do {
            try engine.start()
        } catch {
            log.error("Audio engine start failed: \(error.localizedDescription)")
            return nil
        }
        player.play()
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

    func enqueue(_ packet: Data) {
        guard let converter, !packet.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesPerPacket) else { return }

        lock.lock()
        let backlog = queuedBuffers
        lock.unlock()
        // Keep latency low: drop audio if the device has fallen behind.
        guard backlog < 12 else { return }

        var context = DecodeContext(packet: packet)
        defer {
            context.storage?.deallocate()
            context.description.deallocate()
        }
        var frames = framesPerPacket
        let status = withUnsafeMutablePointer(to: &context) { contextPointer in
            AudioConverterFillComplexBuffer(converter, decodeInputCallback, contextPointer, &frames,
                                            buffer.mutableAudioBufferList, nil)
        }
        guard status == noErr || status == decodeInputExhausted, frames > 0 else { return }
        buffer.frameLength = frames

        lock.lock()
        queuedBuffers += 1
        lock.unlock()
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            lock.lock()
            queuedBuffers -= 1
            lock.unlock()
        }
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
