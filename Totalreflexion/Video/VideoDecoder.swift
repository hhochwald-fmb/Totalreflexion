import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

/// Hardware H.264 decoder that turns AVCC frames into IOSurface-backed pixel buffers.
/// Decoding once and sharing the pixel buffer lets one device appear in several views at no extra cost.
final class VideoDecoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let onFrame: (CVPixelBuffer) -> Void
    private let log = Logger(subsystem: "Totalreflexion", category: "Video")
    private var waitingForKeyframe = true

    init(onFrame: @escaping (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    func configure(sps: Data, pps: Data) {
        var newFormat: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                                ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &newFormat)
            }
        }
        guard status == noErr, let newFormat else {
            log.error("Invalid SPS/PPS: \(status)")
            return
        }
        if let session, VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: newFormat) {
            formatDescription = newFormat
            return
        }
        invalidate()
        formatDescription = newFormat
        createSession(format: newFormat)
        waitingForKeyframe = true
    }

    private func createSession(format: CMVideoFormatDescription) {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer, let refCon else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
                decoder.onFrame(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: format,
            decoderSpecification: [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true]
                as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback, decompressionSessionOut: &newSession)
        guard status == noErr, let newSession else {
            log.error("VTDecompressionSessionCreate failed: \(status)")
            return
        }
        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = newSession
    }

    func decode(_ frame: Data) {
        guard let session, let formatDescription else { return }
        if waitingForKeyframe {
            guard Self.containsIDR(frame) else { return }
            waitingForKeyframe = false
        }

        var blockBuffer: CMBlockBuffer?
        let length = frame.count
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: 0, blockBufferOut: &blockBuffer) == noErr, let blockBuffer else { return }
        let copied = frame.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = length
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: formatDescription,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer) == noErr,
            let sampleBuffer else { return }

        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [],
                                                       frameRefcon: nil, infoFlagsOut: nil)
        if status == kVTInvalidSessionErr {
            invalidate()
            createSession(format: formatDescription)
            waitingForKeyframe = true
        }
    }

    private static func containsIDR(_ frame: Data) -> Bool {
        frame.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            while offset + 5 <= bytes.count {
                let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                    | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                if bytes[offset + 4] & 0x1F == 5 {
                    return true
                }
                offset += 4 + length
            }
            return false
        }
    }
}
