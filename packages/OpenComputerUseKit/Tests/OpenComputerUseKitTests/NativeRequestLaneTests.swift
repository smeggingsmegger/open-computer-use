import XCTest
@testable import OpenComputerUseKit

final class NativeRequestLaneTests: XCTestCase {
    func testCancellationCannotTargetAnotherRequestAndPermanentlyFencesTheLane() throws {
        let lane = NativeRequestLane()
        let token = try XCTUnwrap(lane.begin(id: "request-one"))
        XCTAssertNil(lane.begin(id: "request-two"))
        XCTAssertFalse(lane.cancel(id: "request-two"))
        XCTAssertNoThrow(try token.check())
        let cancelled = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            XCTAssertTrue(lane.cancel(id: "request-one"))
            cancelled.signal()
        }
        XCTAssertEqual(cancelled.wait(timeout: .now() + 3), .success)
        XCTAssertThrowsError(try token.check())
        lane.finish(token)
        XCTAssertTrue(lane.unavailable)
        XCTAssertNil(lane.begin(id: "request-three"))
    }

    func testCompletionOnlyReleasesItsOwnSlotAndEofCancelsActiveWork() throws {
        let lane = NativeRequestLane()
        let first = try XCTUnwrap(lane.begin(id: "one"))
        lane.finish(first)
        let second = try XCTUnwrap(lane.begin(id: "two"))
        lane.finish(first)
        XCTAssertTrue(lane.unavailable)
        XCTAssertNil(lane.begin(id: "three"))
        lane.close()
        XCTAssertThrowsError(try second.check())
        lane.finish(second)
        XCTAssertNil(lane.begin(id: "four"))
    }
}
