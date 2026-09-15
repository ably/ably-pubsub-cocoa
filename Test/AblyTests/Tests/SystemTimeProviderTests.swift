import XCTest
import AblyPubSubDevice.Private

class SystemTimeProviderTests: XCTestCase {
    func test_continuousClock_isAfter() {
        let provider = SystemTimeProvider()

        let preSleepNow = provider.continuousClockNow()
        // Sleep for 0.25s
        usleep(UInt32(0.25 * Double(USEC_PER_SEC)))
        let postSleepNow = provider.continuousClockNow()

        XCTAssertTrue(postSleepNow.isAfter(preSleepNow))
    }

    func test_continuousClock_addingDuration() {
        let provider = SystemTimeProvider()

        let preSleepNow = provider.continuousClockNow()
        let advancedByQuarterSecond = preSleepNow.addingDuration(0.25)
        let advancedByOneSecond = preSleepNow.addingDuration(1)

        // Sleep for 0.5s
        usleep(UInt32(0.5 * Double(USEC_PER_SEC)))

        let postSleepNow = provider.continuousClockNow()
        XCTAssertFalse(advancedByQuarterSecond.isAfter(postSleepNow))
        XCTAssertTrue(advancedByOneSecond.isAfter(postSleepNow))
    }

    func test_schedule_derefsBlockAfterInvoke() {
        let invokedExpectation = self.expectation(description: "scheduled block invoked")

        // retain counter: 1
        var object = NSObject()
        // store reference for above weakified
        weak var weakObject = object

        // schedule a block that captures `object`
        var handle: SchedulerHandle? = SystemTimeProvider().schedule(after: 0, queue: .main, block: { [object] in
            // retain counter +1 -> sum: 2
            _ = object
            invokedExpectation.fulfill()
        })
        _ = handle

        waitForExpectations(timeout: 2, handler: nil)

        // release the handle; the scheduled block (and its captured object) should be released
        handle = nil
        // assign a new object; the old one should now be deallocated
        object = NSObject()

        XCTAssertNil(weakObject)
    }
}
