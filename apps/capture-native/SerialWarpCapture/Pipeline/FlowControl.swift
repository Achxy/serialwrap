import Foundation

/// Credit-based flow control for the streaming pipeline
actor FlowControl {

    /// Current available credits
    private var credits: UInt16 = 0

    /// Waiters for credits
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Maximum credits (for tracking)
    private var maxCredits: UInt16 = 0

    /// Create a flow control instance
    init() {}

    /// Set initial credits (called after START_ACK)
    func setInitialCredits(_ count: UInt16) {
        credits = count
        maxCredits = count

        // Resume any waiters
        resumeWaiters()

        print("[FlowControl] Initial credits set to \(count)")
    }

    /// Wait for a credit to become available
    func waitForCredit() async {
        if credits > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Consume a credit (call before sending a frame)
    /// Returns true if credit was available, false otherwise
    @discardableResult
    func consumeCredit() -> Bool {
        guard credits > 0 else {
            return false
        }
        credits -= 1
        return true
    }

    /// Return credits (called when receiving FRAME_ACK)
    func returnCredits(_ count: UInt16) {
        credits += count

        // Don't exceed max
        if credits > maxCredits {
            credits = maxCredits
        }

        // Resume waiters
        resumeWaiters()
    }

    /// Get current credit count
    var availableCredits: UInt16 {
        credits
    }

    /// Check if credits are available
    var hasCredits: Bool {
        credits > 0
    }

    /// Reset flow control
    func reset() {
        credits = 0
        maxCredits = 0

        // Cancel all waiters
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    /// Resume waiting continuations
    private func resumeWaiters() {
        while credits > 0 && !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
