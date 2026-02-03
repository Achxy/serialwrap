import Foundation

/// Transport protocol for sending and receiving data
protocol Transport: Actor {
    /// Send data to the remote endpoint
    func send(_ data: Data) async throws

    /// Receive data from the remote endpoint
    func receive() async throws -> Data

    /// Check if the transport is still connected
    var isConnected: Bool { get }

    /// Close the transport
    func close() async
}
