import Foundation
import CoreMedia
import VideoToolbox

/// Converts H.264 encoded data between AVCC (length-prefixed) and Annex B (start code) formats
struct NALUConverter {

    /// Annex B start code
    static let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    static let startCodeData = Data(startCode)

    /// Convert VideoToolbox output (AVCC format) to Annex B format
    /// - Parameters:
    ///   - sampleBuffer: The sample buffer from VTCompressionSession
    ///   - includeParameterSets: Whether to include SPS/PPS for keyframes
    /// - Returns: H.264 data in Annex B format
    static func convertToAnnexB(
        _ sampleBuffer: CMSampleBuffer,
        includeParameterSets: Bool = true
    ) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw SerialWarpError.invalidPixelBuffer
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            throw SerialWarpError.encodingFailed(status: status)
        }

        var result = Data()

        // Check if this is a keyframe
        let isKeyframe = isKeyframeSampleBuffer(sampleBuffer)

        // For keyframes, prepend SPS and PPS
        if isKeyframe && includeParameterSets {
            let parameterSets = try extractParameterSets(formatDescription)
            result.append(parameterSets)
        }

        // Convert NAL units from AVCC to Annex B
        var offset = 0
        while offset < totalLength {
            // Read NALU length (4 bytes, big-endian in AVCC)
            let lengthData = Data(bytes: data.advanced(by: offset), count: 4)
            let naluLength = Int(
                UInt32(lengthData[0]) << 24 |
                UInt32(lengthData[1]) << 16 |
                UInt32(lengthData[2]) << 8 |
                UInt32(lengthData[3])
            )
            offset += 4

            guard offset + naluLength <= totalLength else {
                throw SerialWarpError.parseError("Invalid NALU length")
            }

            // Write start code
            result.append(contentsOf: startCode)

            // Write NALU data
            result.append(Data(bytes: data.advanced(by: offset), count: naluLength))
            offset += naluLength
        }

        return result
    }

    /// Extract SPS and PPS from format description in Annex B format
    static func extractParameterSets(_ formatDescription: CMFormatDescription) throws -> Data {
        var result = Data()

        // Get SPS
        var spsSize = 0
        var spsCount = 0
        var spsPointer: UnsafePointer<UInt8>?

        var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: &spsCount,
            nalUnitHeaderLengthOut: nil
        )

        if status == noErr, let sps = spsPointer {
            result.append(contentsOf: startCode)
            result.append(Data(bytes: sps, count: spsSize))
        }

        // Get PPS
        var ppsSize = 0
        var ppsPointer: UnsafePointer<UInt8>?

        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        if status == noErr, let pps = ppsPointer {
            result.append(contentsOf: startCode)
            result.append(Data(bytes: pps, count: ppsSize))
        }

        return result
    }

    /// Check if a sample buffer contains a keyframe
    static func isKeyframeSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else {
            return false
        }

        // Check for kCMSampleAttachmentKey_NotSync - if absent or false, it's a sync frame (keyframe)
        if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }

        // If the key is absent, it's a keyframe
        return true
    }
}
