import XCTest
@testable import SerialWarpCapture

final class FlowControlTests: XCTestCase {

    // MARK: - Initial Credits Tests

    func testInitialCredits() async {
        let flowControl = FlowControl()

        await flowControl.setInitialCredits(8)

        let credits = await flowControl.availableCredits
        XCTAssertEqual(credits, 8)
    }

    func testHasCredits() async {
        let flowControl = FlowControl()

        var hasCredits = await flowControl.hasCredits
        XCTAssertFalse(hasCredits)

        await flowControl.setInitialCredits(5)

        hasCredits = await flowControl.hasCredits
        XCTAssertTrue(hasCredits)
    }

    // MARK: - Credit Consumption Tests

    func testConsumeCredit() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(3)

        let consumed1 = await flowControl.consumeCredit()
        XCTAssertTrue(consumed1)
        XCTAssertEqual(await flowControl.availableCredits, 2)

        let consumed2 = await flowControl.consumeCredit()
        XCTAssertTrue(consumed2)
        XCTAssertEqual(await flowControl.availableCredits, 1)

        let consumed3 = await flowControl.consumeCredit()
        XCTAssertTrue(consumed3)
        XCTAssertEqual(await flowControl.availableCredits, 0)

        // Try to consume when no credits
        let consumed4 = await flowControl.consumeCredit()
        XCTAssertFalse(consumed4)
    }

    // MARK: - Credit Return Tests

    func testReturnCredits() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(4)

        // Consume some credits
        _ = await flowControl.consumeCredit()
        _ = await flowControl.consumeCredit()
        XCTAssertEqual(await flowControl.availableCredits, 2)

        // Return credits
        await flowControl.returnCredits(2)
        XCTAssertEqual(await flowControl.availableCredits, 4)
    }

    func testReturnCreditsDoesNotExceedMax() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(4)

        // Consume one credit
        _ = await flowControl.consumeCredit()
        XCTAssertEqual(await flowControl.availableCredits, 3)

        // Return more credits than consumed (shouldn't exceed initial)
        await flowControl.returnCredits(10)
        XCTAssertEqual(await flowControl.availableCredits, 4)
    }

    // MARK: - Wait for Credit Tests

    func testWaitForCreditWhenAvailable() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(2)

        // Should not block when credits available
        await flowControl.waitForCredit()

        // Credits should still be available (waitForCredit doesn't consume)
        XCTAssertEqual(await flowControl.availableCredits, 2)
    }

    func testWaitForCreditResumesWhenCreditReturned() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(1)

        // Consume the only credit
        _ = await flowControl.consumeCredit()
        XCTAssertEqual(await flowControl.availableCredits, 0)

        // Start waiting in background
        let expectation = XCTestExpectation(description: "Wait resumed")
        let task = Task {
            await flowControl.waitForCredit()
            expectation.fulfill()
        }

        // Give the task time to start waiting
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Return credit should resume waiter
        await flowControl.returnCredits(1)

        await fulfillment(of: [expectation], timeout: 1.0)
        task.cancel()
    }

    // MARK: - Reset Tests

    func testReset() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(5)

        // Consume some credits
        _ = await flowControl.consumeCredit()
        _ = await flowControl.consumeCredit()

        // Reset
        await flowControl.reset()

        XCTAssertEqual(await flowControl.availableCredits, 0)
        XCTAssertFalse(await flowControl.hasCredits)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentConsume() async {
        let flowControl = FlowControl()
        await flowControl.setInitialCredits(100)

        // Spawn multiple concurrent consumers
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await flowControl.consumeCredit()
                }
            }

            var successCount = 0
            for await success in group {
                if success { successCount += 1 }
            }

            XCTAssertEqual(successCount, 100)
        }

        XCTAssertEqual(await flowControl.availableCredits, 0)
    }
}
