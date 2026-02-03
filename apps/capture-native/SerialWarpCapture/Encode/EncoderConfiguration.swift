import Foundation

/// Configuration for the H.264 video encoder
struct EncoderConfiguration: Sendable {
    /// Video width in pixels
    let width: UInt32

    /// Video height in pixels
    let height: UInt32

    /// Target frame rate
    let fps: UInt32

    /// Target bitrate in bits per second
    let bitrateBps: UInt32

    /// Maximum keyframe interval (in frames)
    let maxKeyframeInterval: UInt32

    /// Whether to enable real-time encoding
    let realTime: Bool

    /// H.264 profile level
    let profileLevel: ProfileLevel

    /// Whether to allow frame reordering (B-frames)
    let allowFrameReordering: Bool

    /// Encoder profile levels
    enum ProfileLevel: String, Sendable {
        case baseline = "H264_Baseline_AutoLevel"
        case main = "H264_Main_AutoLevel"
        case high = "H264_High_AutoLevel"
    }

    /// Create an encoder configuration
    init(
        width: UInt32,
        height: UInt32,
        fps: UInt32,
        bitrateBps: UInt32,
        maxKeyframeInterval: UInt32? = nil,
        realTime: Bool = true,
        profileLevel: ProfileLevel = .high,
        allowFrameReordering: Bool = false
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateBps
        self.maxKeyframeInterval = maxKeyframeInterval ?? fps  // Default to 1 second
        self.realTime = realTime
        self.profileLevel = profileLevel
        self.allowFrameReordering = allowFrameReordering
    }

    /// Bitrate in megabits per second
    var bitrateMbps: Double {
        Double(bitrateBps) / 1_000_000
    }

    /// Configuration string for debugging
    var description: String {
        "\(width)x\(height)@\(fps)fps, \(String(format: "%.1f", bitrateMbps))Mbps, \(profileLevel.rawValue)"
    }
}

// MARK: - Standard Configurations

extension EncoderConfiguration {
    /// Configuration for 1080p at 60fps
    static func fhd60(bitrateMbps: UInt32 = 20) -> EncoderConfiguration {
        EncoderConfiguration(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateBps: bitrateMbps * 1_000_000
        )
    }

    /// Configuration for 1440p at 60fps
    static func qhd60(bitrateMbps: UInt32 = 30) -> EncoderConfiguration {
        EncoderConfiguration(
            width: 2560,
            height: 1440,
            fps: 60,
            bitrateBps: bitrateMbps * 1_000_000
        )
    }

    /// Configuration for 4K at 60fps
    static func uhd60(bitrateMbps: UInt32 = 50) -> EncoderConfiguration {
        EncoderConfiguration(
            width: 3840,
            height: 2160,
            fps: 60,
            bitrateBps: bitrateMbps * 1_000_000
        )
    }
}
