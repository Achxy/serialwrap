import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Delegate protocol for encoder events
protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didEncodeFrame frame: EncodedFrame)
    func videoEncoder(_ encoder: VideoEncoder, didEncounterError error: Error)
}

/// H.264 video encoder using VideoToolbox
actor VideoEncoder {

    /// Delegate for encoder callbacks
    weak var delegate: VideoEncoderDelegate?

    /// Compression session
    private var session: VTCompressionSession?

    /// Whether the encoder is ready
    private(set) var isReady: Bool = false

    /// Current configuration
    private(set) var configuration: EncoderConfiguration?

    /// Frame number counter
    private var frameNumber: UInt64 = 0

    /// Continuation for async stream
    private var frameContinuation: AsyncThrowingStream<EncodedFrame, Error>.Continuation?

    /// Create a video encoder
    init() {}

    /// Configure the encoder
    /// - Parameter config: Encoder configuration
    func configure(_ config: EncoderConfiguration) throws {
        // Clean up existing session
        if let existingSession = session {
            VTCompressionSessionInvalidate(existingSession)
            session = nil
        }

        var newSession: VTCompressionSession?

        // Create compression session
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: config.width,
                kCVPixelBufferHeightKey: config.height
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &newSession
        )

        guard status == noErr, let session = newSession else {
            throw SerialWarpError.encoderCreationFailed(status: status)
        }

        // Configure encoder properties
        try configureSession(session, with: config)

        // Prepare to encode
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            VTCompressionSessionInvalidate(session)
            throw SerialWarpError.encoderCreationFailed(status: prepareStatus)
        }

        self.session = session
        self.configuration = config
        self.isReady = true
        self.frameNumber = 0

        print("[Encoder] Configured: \(config.description)")
    }

    /// Configure session properties
    private func configureSession(_ session: VTCompressionSession, with config: EncoderConfiguration) throws {
        // Real-time encoding
        var status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: config.realTime ? kCFBooleanTrue : kCFBooleanFalse
        )
        guard status == noErr else {
            throw SerialWarpError.propertySetFailed(property: "RealTime", status: status)
        }

        // Profile level
        let profileValue: CFString
        switch config.profileLevel {
        case .baseline:
            profileValue = kVTProfileLevel_H264_Baseline_AutoLevel
        case .main:
            profileValue = kVTProfileLevel_H264_Main_AutoLevel
        case .high:
            profileValue = kVTProfileLevel_H264_High_AutoLevel
        }

        status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: profileValue
        )
        guard status == noErr else {
            throw SerialWarpError.propertySetFailed(property: "ProfileLevel", status: status)
        }

        // Average bitrate
        status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: NSNumber(value: config.bitrateBps)
        )
        guard status == noErr else {
            throw SerialWarpError.propertySetFailed(property: "AverageBitRate", status: status)
        }

        // Max keyframe interval
        status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: NSNumber(value: config.maxKeyframeInterval)
        )
        guard status == noErr else {
            throw SerialWarpError.propertySetFailed(property: "MaxKeyFrameInterval", status: status)
        }

        // Frame reordering (B-frames)
        status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: config.allowFrameReordering ? kCFBooleanTrue : kCFBooleanFalse
        )
        guard status == noErr else {
            throw SerialWarpError.propertySetFailed(property: "AllowFrameReordering", status: status)
        }

        // Expected frame rate
        status = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: NSNumber(value: config.fps)
        )
        // This property might not be supported, so we don't throw on failure
    }

    /// Encode a captured frame
    /// - Parameter frame: The captured frame to encode
    /// - Returns: The encoded frame, or nil if encoding is asynchronous
    func encode(_ frame: CapturedFrame) async throws -> EncodedFrame? {
        guard isReady, let session = session else {
            throw SerialWarpError.encoderNotReady
        }

        let currentFrameNumber = frameNumber
        frameNumber += 1

        // Create frame properties for forcing keyframes if needed
        let frameProperties: CFDictionary? = nil

        // Use VTCompressionSessionEncodeFrameWithOutputHandler for synchronous encoding
        var encodedFrame: EncodedFrame?
        var encodeError: Error?

        let status = VTCompressionSessionEncodeFrameWithOutputHandler(
            session,
            imageBuffer: frame.pixelBuffer,
            presentationTimeStamp: frame.presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            infoFlagsOut: nil
        ) { [weak self] status, infoFlags, sampleBuffer in
            guard status == noErr else {
                encodeError = SerialWarpError.encodingFailed(status: status)
                return
            }

            guard let sampleBuffer = sampleBuffer else {
                return
            }

            do {
                // Convert to Annex B format
                let annexBData = try NALUConverter.convertToAnnexB(sampleBuffer)
                let isKeyframe = NALUConverter.isKeyframeSampleBuffer(sampleBuffer)

                let metadata = FrameMetadata(
                    frameNumber: currentFrameNumber,
                    ptsUs: frame.ptsUs,
                    captureTsUs: UInt64(Date().timeIntervalSince1970 * 1_000_000),
                    isKeyframe: isKeyframe
                )

                encodedFrame = EncodedFrame(metadata: metadata, data: annexBData)

                // Notify delegate
                Task { @MainActor in
                    if let encoded = encodedFrame, let delegate = await self?.delegate {
                        delegate.videoEncoder(self!, didEncodeFrame: encoded)
                    }
                }
            } catch {
                encodeError = error
            }
        }

        if status != noErr {
            throw SerialWarpError.encodingFailed(status: status)
        }

        if let error = encodeError {
            throw error
        }

        return encodedFrame
    }

    /// Start encoding with an async stream output
    func startEncoding() -> AsyncThrowingStream<EncodedFrame, Error> {
        AsyncThrowingStream { continuation in
            self.frameContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.handleEncodingTermination() }
            }
        }
    }

    /// Yield an encoded frame to the async stream
    func yieldFrame(_ frame: EncodedFrame) {
        frameContinuation?.yield(frame)
    }

    /// Stop encoding
    func stopEncoding() {
        frameContinuation?.finish()
        frameContinuation = nil
    }

    /// Handle encoding termination
    private func handleEncodingTermination() {
        stopEncoding()
    }

    /// Flush any pending frames
    func flush() async throws {
        guard let session = session else { return }

        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else {
            throw SerialWarpError.flushFailed(status: status)
        }
    }

    /// Invalidate the encoder
    func invalidate() {
        if let session = session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
        isReady = false
        configuration = nil
        stopEncoding()
    }

    /// Force a keyframe on the next encode
    func forceKeyframe() {
        // This would be implemented by setting frame properties on the next encode call
    }
}
