import Foundation
import CoreGraphics

/// Delegate protocol for pipeline events
@MainActor
protocol StreamingPipelineDelegate: AnyObject {
    func pipeline(_ pipeline: StreamingPipeline, didChangeState state: PipelineState)
    func pipeline(_ pipeline: StreamingPipeline, didUpdateStats stats: PipelineStats)
    func pipeline(_ pipeline: StreamingPipeline, didCapturePreviewFrame frame: CGImage)
    func pipeline(_ pipeline: StreamingPipeline, didEncounterError error: Error)
}

/// Main streaming pipeline that coordinates all components
@available(macOS 12.3, *)
actor StreamingPipeline {

    /// Delegate for pipeline events
    weak var delegate: StreamingPipelineDelegate?

    /// Current pipeline state
    private(set) var state: PipelineState = .disconnected {
        didSet {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.delegate?.pipeline(self, didChangeState: await self.state)
            }
        }
    }

    /// Transport for USB communication
    private var transport: (any Transport)?

    /// Virtual display manager
    private let displayManager = VirtualDisplayManager.shared

    /// Capture service
    private let captureService = CaptureService()

    /// Video encoder
    private let encoder = VideoEncoder()

    /// Flow control
    private let flowControl = FlowControl()

    /// Current sequence number
    private var sequence: UInt32 = 0

    /// Pipeline statistics
    private var stats = PipelineStats()

    /// Stream configuration
    private var streamConfig: StreamConfiguration?

    /// Capture task
    private var captureTask: Task<Void, Never>?

    /// Receive task (for handling incoming packets)
    private var receiveTask: Task<Void, Never>?

    /// Stats update task
    private var statsTask: Task<Void, Never>?

    /// Create a streaming pipeline
    init() {}

    // MARK: - Public API

    /// Connect to a USB device
    func connect() async throws {
        guard state == .disconnected || state == .error else {
            throw SerialWarpError.captureFailed("Invalid state for connect: \(state)")
        }

        state = .connecting

        do {
            let usbTransport = try await USBTransport.open()
            transport = usbTransport
            state = .connected

            print("[Pipeline] Connected to USB device: \(usbTransport.deviceInfo.name)")

            // Perform handshake
            try await performHandshake()

        } catch {
            state = .error
            throw error
        }
    }

    /// Start streaming with the given configuration
    func startStreaming(config: StreamConfiguration) async throws {
        guard state == .ready else {
            throw SerialWarpError.captureFailed("Invalid state for startStreaming: \(state)")
        }

        streamConfig = config
        state = .starting

        do {
            // Create virtual display
            let displayConfig = DisplayConfiguration(
                width: config.width,
                height: config.height,
                refreshRate: config.fps,
                hidpiEnabled: config.hidpi
            )

            let displayId = try await MainActor.run {
                try displayManager.create(config: displayConfig)
            }

            // Configure encoder
            let encoderConfig = EncoderConfiguration(
                width: config.width,
                height: config.height,
                fps: config.fps,
                bitrateBps: config.bitrateBps
            )
            try await encoder.configure(encoderConfig)

            // Send START packet
            try await sendStartPacket(config: config)

            // Start capture
            let captureConfig = CaptureConfiguration(
                width: config.width,
                height: config.height,
                fps: config.fps
            )

            let frameStream = try await captureService.startCapture(displayId: displayId, config: captureConfig)

            // Reset stats
            stats.reset()
            stats.startTime = Date()

            state = .streaming

            // Start receive task
            startReceiveTask()

            // Start stats task
            startStatsTask()

            // Start capture/encode/send loop
            captureTask = Task {
                await runCaptureLoop(frameStream: frameStream)
            }

        } catch {
            state = .error
            throw error
        }
    }

    /// Stop streaming
    func stopStreaming() async {
        guard state == .streaming else { return }

        state = .stopping

        // Cancel tasks
        captureTask?.cancel()
        receiveTask?.cancel()
        statsTask?.cancel()

        captureTask = nil
        receiveTask = nil
        statsTask = nil

        // Stop capture
        await captureService.stopCapture()

        // Invalidate encoder
        await encoder.invalidate()

        // Destroy virtual display
        await MainActor.run {
            displayManager.destroy()
        }

        // Send STOP packet
        do {
            try await sendStopPacket()
        } catch {
            print("[Pipeline] Error sending STOP: \(error)")
        }

        // Reset flow control
        await flowControl.reset()

        state = .ready
    }

    /// Disconnect from USB device
    func disconnect() async {
        if state == .streaming {
            await stopStreaming()
        }

        if let transport = transport {
            await transport.close()
            self.transport = nil
        }

        state = .disconnected
    }

    // MARK: - Handshake

    /// Perform HELLO handshake
    private func performHandshake() async throws {
        guard let transport = transport else {
            throw SerialWarpError.disconnected
        }

        state = .handshaking

        // Send HELLO
        let hello = HelloPayload(
            softwareVersion: 1,
            maxWidth: 3840,
            maxHeight: 2160,
            maxFps: 120,
            capabilities: SWRPConstants.Capabilities.hidpi
        )

        let helloPacket = Packet.hello(sequence: nextSequence(), payload: hello)
        try await transport.send(helloPacket.toBytes())

        // Receive HELLO_ACK
        let response = try await transport.receive()
        let (ackPacket, _) = try Packet.parse(response)

        guard ackPacket.packetType == .helloAck else {
            throw SerialWarpError.unexpectedPacketType(expected: "HELLO_ACK", actual: ackPacket.packetType.rawValue)
        }

        // Parse HELLO_ACK payload
        let ackPayload = try HelloPayload.parse(ackPacket.payload)
        print("[Pipeline] Handshake complete. Sink capabilities: hidpi=\(ackPayload.supportsHidpi)")

        state = .ready
    }

    /// Send START packet and wait for START_ACK
    private func sendStartPacket(config: StreamConfiguration) async throws {
        guard let transport = transport else {
            throw SerialWarpError.disconnected
        }

        let start = StartPayload(
            width: config.width,
            height: config.height,
            fps: config.fps,
            bitrateBps: config.bitrateBps
        )

        let startPacket = Packet.start(sequence: nextSequence(), payload: start)
        try await transport.send(startPacket.toBytes())

        // Wait for START_ACK
        let response = try await transport.receive()
        let (ackPacket, _) = try Packet.parse(response)

        guard ackPacket.packetType == .startAck else {
            throw SerialWarpError.unexpectedPacketType(expected: "START_ACK", actual: ackPacket.packetType.rawValue)
        }

        let ackPayload = try StartAckPayload.parse(ackPacket.payload)

        guard ackPayload.isOk else {
            throw SerialWarpError.handshakeFailed("START rejected with status: \(ackPayload.status)")
        }

        // Set initial credits
        await flowControl.setInitialCredits(ackPayload.initialCredits)

        print("[Pipeline] START acknowledged, initial credits: \(ackPayload.initialCredits)")
    }

    /// Send STOP packet
    private func sendStopPacket() async throws {
        guard let transport = transport else { return }

        let stopPacket = Packet.stop(sequence: nextSequence())
        try await transport.send(stopPacket.toBytes())

        // Wait for STOP_ACK (with timeout)
        // For simplicity, we don't wait for STOP_ACK here
    }

    // MARK: - Capture Loop

    /// Main capture/encode/send loop
    private func runCaptureLoop(frameStream: AsyncThrowingStream<CapturedFrame, Error>) async {
        do {
            for try await frame in frameStream {
                guard !Task.isCancelled else { break }

                stats.framesCaptured += 1

                // Create preview image
                if let previewImage = captureService.createPreviewImage(from: frame) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.delegate?.pipeline(self, didCapturePreviewFrame: previewImage)
                    }
                }

                // Encode frame
                guard let encodedFrame = try await encoder.encode(frame) else {
                    continue
                }

                stats.framesEncoded += 1

                // Wait for credit
                await flowControl.waitForCredit()

                // Send frame
                try await sendFrame(encodedFrame)
            }
        } catch {
            if !Task.isCancelled {
                print("[Pipeline] Capture loop error: \(error)")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.delegate?.pipeline(self, didEncounterError: error)
                }
            }
        }
    }

    /// Send an encoded frame
    private func sendFrame(_ frame: EncodedFrame) async throws {
        guard let transport = transport else {
            throw SerialWarpError.disconnected
        }

        // Segment the frame
        let segments = frame.intoSegments()

        for segment in segments {
            // Consume a credit for this segment
            await flowControl.consumeCredit()

            // Create frame header
            let frameHeader = FrameHeader(
                frameNumber: frame.metadata.frameNumber,
                ptsUs: frame.metadata.ptsUs,
                captureTsUs: frame.metadata.captureTsUs,
                frameSize: segment.frameSize,
                segmentIndex: segment.segmentIndex,
                segmentCount: segment.segmentCount
            )

            // Create and send packet
            let packet = Packet.frame(sequence: nextSequence(), header: frameHeader, data: segment.data)
            let packetData = packet.toBytes()

            try await transport.send(packetData)

            stats.framesSent += 1
            stats.bytesSent += UInt64(packetData.count)
        }
    }

    // MARK: - Receive Task

    /// Start the receive task for handling incoming packets
    private func startReceiveTask() {
        receiveTask = Task {
            await receiveLoop()
        }
    }

    /// Receive loop for handling FRAME_ACK and other packets
    private func receiveLoop() async {
        guard let transport = transport else { return }

        while !Task.isCancelled {
            do {
                let data = try await transport.receive()
                let (packet, _) = try Packet.parse(data)

                switch packet.packetType {
                case .frameAck:
                    let ack = try FrameAckPayload.parse(packet.payload)
                    await flowControl.returnCredits(ack.creditsReturned)
                    stats.latencyUs = UInt64(Date().timeIntervalSince1970 * 1_000_000) - ack.frameNumber

                case .ping:
                    let ping = try PingPayload.parse(packet.payload)
                    let pong = PongPayload(respondingTo: ping)
                    let pongPacket = Packet.pong(sequence: nextSequence(), payload: pong)
                    try await transport.send(pongPacket.toBytes())

                default:
                    print("[Pipeline] Received unexpected packet: \(packet.packetType)")
                }

            } catch {
                if !Task.isCancelled {
                    print("[Pipeline] Receive error: \(error)")
                    break
                }
            }
        }
    }

    // MARK: - Stats

    /// Start stats update task
    private func startStatsTask() {
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                guard !Task.isCancelled else { break }

                // Calculate FPS
                let elapsed = stats.elapsedSeconds
                if elapsed > 0 {
                    stats.currentFps = Double(stats.framesCaptured) / elapsed
                    stats.currentBitrateBps = UInt64(Double(stats.bytesSent * 8) / elapsed)
                }

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.delegate?.pipeline(self, didUpdateStats: await self.stats)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Get next sequence number
    private func nextSequence() -> UInt32 {
        let seq = sequence
        sequence += 1
        return seq
    }

    /// Get current statistics
    func getStats() -> PipelineStats {
        stats
    }
}

// MARK: - Stream Configuration

/// Configuration for streaming
struct StreamConfiguration: Sendable {
    let width: UInt32
    let height: UInt32
    let fps: UInt32
    let bitrateBps: UInt32
    let hidpi: Bool

    init(width: UInt32, height: UInt32, fps: UInt32, bitrateMbps: UInt32, hidpi: Bool = false) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateMbps * 1_000_000
        self.hidpi = hidpi
    }

    /// Default 1080p60 configuration
    static let fhd60 = StreamConfiguration(width: 1920, height: 1080, fps: 60, bitrateMbps: 20)

    /// 1440p60 configuration
    static let qhd60 = StreamConfiguration(width: 2560, height: 1440, fps: 60, bitrateMbps: 30)

    /// 4K60 configuration
    static let uhd60 = StreamConfiguration(width: 3840, height: 2160, fps: 60, bitrateMbps: 50)
}
