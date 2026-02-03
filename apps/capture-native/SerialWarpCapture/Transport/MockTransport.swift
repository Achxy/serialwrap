import Foundation

/// Mock transport for testing that uses channels
actor MockTransport: Transport {

    /// Data to be received
    private var receiveQueue: [Data] = []

    /// Data that was sent
    private var sentData: [Data] = []

    /// Continuations waiting for data
    private var waiters: [CheckedContinuation<Data, Error>] = []

    /// Whether the transport is connected
    private(set) var isConnected: Bool = true

    /// Create a mock transport
    init() {}

    /// Queue data to be received
    func queueReceive(_ data: Data) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: data)
        } else {
            receiveQueue.append(data)
        }
    }

    /// Queue multiple data items to be received
    func queueReceive(_ items: [Data]) {
        for data in items {
            queueReceive(data)
        }
    }

    /// Get all data that was sent
    func getSentData() -> [Data] {
        sentData
    }

    /// Clear sent data
    func clearSentData() {
        sentData.removeAll()
    }

    // MARK: - Transport Protocol

    func send(_ data: Data) async throws {
        guard isConnected else {
            throw SerialWarpError.disconnected
        }
        sentData.append(data)
    }

    func receive() async throws -> Data {
        guard isConnected else {
            throw SerialWarpError.disconnected
        }

        if let data = receiveQueue.first {
            receiveQueue.removeFirst()
            return data
        }

        // Wait for data
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() async {
        isConnected = false

        // Cancel all waiters
        for waiter in waiters {
            waiter.resume(throwing: SerialWarpError.disconnected)
        }
        waiters.removeAll()
    }
}

// MARK: - Mock Transport Pair

/// Create a pair of connected mock transports
func createMockTransportPair() -> (MockTransportPair) {
    MockTransportPair()
}

/// A pair of mock transports that are connected to each other
final class MockTransportPair: @unchecked Sendable {
    let source: MockTransport
    let sink: MockTransport

    private let lock = NSLock()

    init() {
        source = MockTransport()
        sink = MockTransport()
    }

    /// Forward data from source to sink
    func forwardSourceToSink(_ data: Data) async {
        await sink.queueReceive(data)
    }

    /// Forward data from sink to source
    func forwardSinkToSource(_ data: Data) async {
        await source.queueReceive(data)
    }
}
