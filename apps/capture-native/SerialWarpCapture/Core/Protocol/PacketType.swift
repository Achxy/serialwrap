import Foundation

/// SWRP packet types matching the Rust protocol definition
enum PacketType: UInt8, Sendable, CaseIterable {
    case hello = 0x01
    case helloAck = 0x02
    case start = 0x03
    case startAck = 0x04
    case frame = 0x10
    case frameAck = 0x11
    case stop = 0x30
    case stopAck = 0x31
    case ping = 0x40
    case pong = 0x41

    /// Human-readable description of the packet type
    var description: String {
        switch self {
        case .hello: return "HELLO"
        case .helloAck: return "HELLO_ACK"
        case .start: return "START"
        case .startAck: return "START_ACK"
        case .frame: return "FRAME"
        case .frameAck: return "FRAME_ACK"
        case .stop: return "STOP"
        case .stopAck: return "STOP_ACK"
        case .ping: return "PING"
        case .pong: return "PONG"
        }
    }

    /// Whether this packet type is a request (vs a response)
    var isRequest: Bool {
        switch self {
        case .hello, .start, .frame, .stop, .ping:
            return true
        case .helloAck, .startAck, .frameAck, .stopAck, .pong:
            return false
        }
    }

    /// The expected response type for request packets
    var expectedResponse: PacketType? {
        switch self {
        case .hello: return .helloAck
        case .start: return .startAck
        case .frame: return .frameAck
        case .stop: return .stopAck
        case .ping: return .pong
        default: return nil
        }
    }
}
