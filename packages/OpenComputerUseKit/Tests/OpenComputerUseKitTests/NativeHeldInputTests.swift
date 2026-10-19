import XCTest
import CoreGraphics
@testable import OpenComputerUseKit

final class NativeHeldInputTests: XCTestCase {
    func testCancelledShortcutReleasesOnlySubmittedKeysInReverseOrder() {
        for boundary in 1...3 {
            let token = NativeOperationCancellation()
            var events: [(CGEventType, Int64, CGEventFlags)] = []
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { event, _ in
                events.append((event.type, event.getIntegerValueField(.keyboardEventKeycode), event.flags))
                if events.count == boundary { token.cancel() }
            }, cancellation: token) {
                try InputSimulation.pressKey("super+shift+a", pid: 42)
            })
            XCTAssertEqual(events.count, boundary * 2)
            XCTAssertEqual(events.last?.2, [])
            XCTAssertEqual(Array(events.prefix(boundary).map { $0.1 }.reversed()), events.suffix(boundary).map { $0.1 })
            if boundary == 3 { XCTAssertEqual(events[3].0, .keyUp); XCTAssertEqual(events[3].2, [.maskCommand, .maskShift]) }
        }
    }

    func testPrivateDownGetsOnlyPrivateCleanupWhenCompanionInputIsCancelled() throws {
        let token = NativeOperationCancellation()
        var events: [CGEventType] = []
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in XCTAssertEqual(pid, 42) }, send: { _, _ in XCTFail("No public down or release was authorized") }, cancellation: token) {
            try NativeInputGuard.postPrivate(down, pid: 42) { event, _ in events.append(event.type); token.cancel() }
            try NativeInputGuard.post(down, pid: 42)
        })
        XCTAssertEqual(events, [.leftMouseDown, .leftMouseUp])
    }

    func testGlobalCleanupUsesLatestDragPositionAndRefusesAChangedHitTarget() throws {
        let token = NativeOperationCancellation()
        var events: [CGEventType] = []
        var points: [CGPoint] = []
        let start = CGPoint(x: 10, y: 20), end = CGPoint(x: 30, y: 40)
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in XCTAssertEqual(pid, 42) }, hitTest: { point in
            points.append(point)
            return points.count <= 2 ? 42 : 99
        }, sendGlobal: { event in events.append(event.type) }, cancellation: token) {
            try NativeInputGuard.postGlobal(XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)))
            try NativeInputGuard.postGlobal(XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left)))
            token.cancel()
            try NativeInputGuard.validate(pid: 42)
        })
        XCTAssertEqual(points, [start, end, end])
        XCTAssertEqual(events, [.leftMouseDown, .leftMouseDragged])
    }
}
