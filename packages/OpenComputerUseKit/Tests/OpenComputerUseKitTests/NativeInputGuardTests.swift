import CoreGraphics
import ApplicationServices
import XCTest
@testable import OpenComputerUseKit

final class NativeInputGuardTests: XCTestCase {
    func testAccessibilityFallbackRetainsSourceReviewAndRestoresItsScope() throws {
        let element = AXUIElementCreateApplication(getpid())
        var sourceMatches = true
        var dispatched = 0
        try NativeInputGuard.withValidation({ _ in }) {
            XCTAssertThrowsError(try NativeInputGuard.withAccessibilityTargetReview({
                if !sourceMatches { throw ComputerUseError.stateUnavailable("Original target changed") }
            }) {
                try NativeInputGuard.withAccessibilityTargetReview({}) {
                    _ = try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                        dispatched += 1
                        sourceMatches = false
                        return .actionUnsupported
                    })
                    _ = try NativeInputGuard.setAttribute(element, kAXFocusedAttribute as CFString, kCFBooleanTrue, send: { _, _, _ in
                        XCTFail("Fallback dispatched after source changed")
                        return .success
                    })
                }
            })
            // A completed/failed sequence cannot constrain later inspection.
            _ = try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                dispatched += 1
                return .success
            })
        }
        XCTAssertEqual(dispatched, 2)
    }

    func testDragDoesNotPressWhenDestinationChangesDuringAppValidation() throws {
        for global in [false, true] {
            var destinationMatches = true
            var validations = 0
            var events: [CGEventType] = []
            let send: (CGEvent, pid_t) -> Void = { event, _ in events.append(event.type) }
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in
                validations += 1
                if validations == 2 { destinationMatches = false }
            }, send: send, hitTest: { _ in 42 }, sendGlobal: { send($0, 42) }) {
                try NativeInputGuard.withMouseTargetReview({
                    if !destinationMatches { throw ComputerUseError.stateUnavailable("Drag destination changed") }
                }) {
                    if global {
                        try InputSimulation.dragGlobally(from: .zero, to: CGPoint(x: 20, y: 20))
                    } else {
                        try InputSimulation.dragTargeted(from: .zero, to: CGPoint(x: 20, y: 20), pid: 42)
                    }
                }
            })
            XCTAssertEqual(events, [.mouseMoved])
        }
    }

    func testCoordinateReviewStopsMouseFallbackAfterAccessibilityTargetChanges() throws {
        let element = AXUIElementCreateApplication(getpid())
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        var coordinateMatches = true
        var attempts = 0
        let review = {
            if !coordinateMatches { throw ComputerUseError.stateUnavailable("Coordinate target replaced") }
        }
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { _, _ in
            XCTFail("Mouse fallback reached a replacement coordinate target")
        }) {
            try NativeInputGuard.withAccessibilityTargetReview(review) {
                try NativeInputGuard.withMouseTargetReview(review) {
                    let result = try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                        attempts += 1
                        coordinateMatches = false
                        return .actionUnsupported
                    })
                    XCTAssertEqual(result, .actionUnsupported)
                    try NativeInputGuard.post(down, pid: 42)
                }
            }
        })
        XCTAssertEqual(attempts, 1)
    }

    func testChangedMouseTargetBlocksSecondClickButAllowsReleaseOnEveryRoute() throws {
        for route in 0..<3 {
            var current = true
            var events: [CGEventType] = []
            let send: (CGEvent, pid_t) -> Void = { event, _ in
                events.append(event.type)
                if event.type == .leftMouseDown { current = false }
            }
            let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
            let up = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: .zero, mouseButton: .left))
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: send, hitTest: { _ in 42 }, sendGlobal: { send($0, 42) }) {
                try NativeInputGuard.withMouseTargetReview({
                    if !current { throw ComputerUseError.stateUnavailable("Target changed") }
                }) {
                    for event in [down, up, down] {
                        switch route {
                        case 0: try NativeInputGuard.post(event, pid: 42)
                        case 1: try NativeInputGuard.postPrivate(event, pid: 42, send: send)
                        default: try NativeInputGuard.postGlobal(event)
                        }
                    }
                }
            })
            XCTAssertEqual(events, [.leftMouseDown, .leftMouseUp], "route \(route)")
        }
    }

    func testCancellationDuringMouseReviewFencesDispatchAndReviewDoesNotLeak() throws {
        let cancellation = NativeOperationCancellation()
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        var reviews = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { _, _ in XCTFail("Input after cancellation") }, cancellation: cancellation) {
            try NativeInputGuard.withMouseTargetReview({
                reviews += 1
                if reviews == 2 { cancellation.cancel() }
            }) { try NativeInputGuard.post(down, pid: 42) }
        })
        XCTAssertEqual(reviews, 2)
        try NativeInputGuard.withValidation({ _ in }, send: { _, _ in }) {
            XCTAssertThrowsError(try NativeInputGuard.withMouseTargetReview({
                throw ComputerUseError.stateUnavailable("Old review")
            }) {})
            XCTAssertNoThrow(try NativeInputGuard.post(down, pid: 42))
        }
    }

    func testChangedFocusStopsTheNextKeyDownButAllowsRelease() throws {
        var focusMatches = true
        var events: [CGEventType] = []
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { event, _ in
            events.append(event.type)
            if event.type == .keyDown { focusMatches = false }
        }) {
            try NativeInputGuard.withKeyboardTargetReview({
                if !focusMatches { throw ComputerUseError.stateUnavailable("Focus changed") }
            }) {
                try InputSimulation.pressKey("a", pid: 42)
                try InputSimulation.pressKey("b", pid: 42)
            }
        })
        XCTAssertEqual(events, [.keyDown, .keyUp])
    }

    func testKeyboardReviewDoesNotEscapeItsOperationAndCancellationFencesDispatch() throws {
        let cancellation = NativeOperationCancellation()
        var events: [CGEventType] = []
        try NativeInputGuard.withValidation({ _ in }, send: { event, _ in events.append(event.type) }) {
            XCTAssertThrowsError(try NativeInputGuard.withKeyboardTargetReview({
                throw ComputerUseError.stateUnavailable("Stale target")
            }) { try InputSimulation.pressKey("a", pid: 42) })
            try InputSimulation.pressKey("b", pid: 42)
        }
        XCTAssertEqual(events, [.keyDown, .keyUp])
        var reviews = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { _, _ in XCTFail("Input after cancellation") }, cancellation: cancellation) {
            try NativeInputGuard.withKeyboardTargetReview({
                reviews += 1
                if reviews == 2 { cancellation.cancel() }
            }) { try InputSimulation.pressKey("a", pid: 42) }
        })
        XCTAssertEqual(reviews, 2)
    }

    func testCancellationFromAnotherThreadStopsTheNextInputEvent() throws {
        let cancellation = NativeOperationCancellation()
        var events: [CGEventType] = []
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { event, _ in
            events.append(event.type)
            let stopped = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                cancellation.cancel()
                stopped.signal()
            }
            XCTAssertEqual(stopped.wait(timeout: .now() + 3), .success)
        }, cancellation: cancellation) {
            try InputSimulation.pressKey("a", pid: 42)
        })
        XCTAssertEqual(events, [.keyDown, .keyUp]) // only the cleanup release follows cancellation
        XCTAssertThrowsError(try cancellation.check())
        // A cancelled operation cannot poison an independent next operation.
        XCTAssertNoThrow(try NativeInputGuard.withValidation({ _ in }, send: { _, _ in }, cancellation: NativeOperationCancellation()) {
            try InputSimulation.pressKey("a", pid: 42)
        })
    }

    func testCancellationDuringIdentityValidationPreventsDispatch() throws {
        let cancellation = NativeOperationCancellation()
        var sent = false
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in cancellation.cancel() }, send: { _, _ in sent = true }, cancellation: cancellation) {
            try NativeInputGuard.post(event, pid: 42)
        })
        XCTAssertFalse(sent)
    }

    func testCancelledScopeRefusesBeforeInspectionOrGlobalInput() {
        let cancellation = NativeOperationCancellation()
        cancellation.cancel()
        var entered = false
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in XCTFail("No inspection after cancellation") }, hitTest: { _ in XCTFail("No hit test after cancellation"); return 42 }, sendGlobal: { _ in XCTFail("No global input after cancellation") }, cancellation: cancellation) {
            entered = true
        })
        XCTAssertFalse(entered)
    }

    func testShortcutReleasesModifiersWithOnlyTheRemainingFlags() throws {
        var events: [(CGEventType, CGEventFlags)] = []
        try NativeInputGuard.withValidation({ pid in XCTAssertEqual(pid, 42) }, send: { event, _ in
            events.append((event.type, event.flags))
        }) {
            try InputSimulation.pressKey("super+shift+a", pid: 42)
        }
        XCTAssertEqual(events.map { $0.0.rawValue }, [CGEventType.flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged].map { $0.rawValue })
        XCTAssertEqual(events.count, 6)
        guard events.count == 6 else { return }
        XCTAssertEqual(events[2].1, [.maskCommand, .maskShift])
        XCTAssertEqual(events[3].1, [.maskCommand, .maskShift])
        XCTAssertEqual(events[4].1, events[0].1)
        XCTAssertEqual(events[5].1, [])
    }

    func testRequiredBindingRefusesMissingScopeBeforeAnyDispatch() throws {
        let oldValue = ProcessInfo.processInfo.environment["TAFFY_REQUIRE_APP_IDENTITY"]
        setenv("TAFFY_REQUIRE_APP_IDENTITY", "1", 1)
        defer {
            if let oldValue { setenv("TAFFY_REQUIRE_APP_IDENTITY", oldValue, 1) }
            else { unsetenv("TAFFY_REQUIRE_APP_IDENTITY") }
        }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        var sent = false
        XCTAssertThrowsError(try NativeInputGuard.post(event, pid: 42, sendUnbound: { _, _ in sent = true }))
        XCTAssertThrowsError(try NativeInputGuard.postGlobal(event, sendUnbound: { _ in sent = true }))
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertThrowsError(try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in sent = true; return .success }))
        XCTAssertFalse(sent)
        let checked = expectation(description: "other thread refuses missing guard")
        try NativeInputGuard.withValidation({ _ in }, send: { _, _ in }) {
            Thread.detachNewThread {
                do {
                    try NativeInputGuard.validate(pid: 42)
                    XCTFail("A different thread accepted input without its required guard")
                } catch {}
                checked.fulfill()
            }
            wait(for: [checked], timeout: 3)
        }
    }

    func testTypingRevalidatesBeforeEachEventAndStopsOnChangedIdentity() {
        var checks = 0
        var sent = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in
            XCTAssertEqual(pid, 42)
            checks += 1
            if checks >= 2 { throw ComputerUseError.permissionDenied("App changed") }
        }, send: { _, _ in sent += 1 }) {
            try InputSimulation.typeText(String(repeating: "x", count: 140), pid: 42)
        })
        XCTAssertEqual(checks, 3) // cleanup revalidates and must also refuse
        XCTAssertEqual(sent, 1)
        // The failed operation must not leave a guard on the next request.
        XCTAssertNoThrow(try NativeInputGuard.validate(pid: 99))
    }

    func testDragStopsBeforeDispatchWhenTheTargetChangesMidGesture() {
        var checks = 0
        var sent = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in
            checks += 1
            if checks >= 3 { throw ComputerUseError.permissionDenied("App restarted") }
        }, send: { _, _ in sent += 1 }) {
            try InputSimulation.dragTargeted(from: .zero, to: CGPoint(x: 100, y: 100), pid: 42)
        })
        XCTAssertEqual(checks, 4) // no release to the replacement process
        XCTAssertEqual(sent, 2)
    }

    func testWrongTargetCannotReceiveAKeyOrScrollEvent() {
        var sent = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in
            guard pid == 42 else { throw ComputerUseError.permissionDenied("Wrong target") }
        }, send: { _, _ in sent += 1 }) {
            try InputSimulation.pressKey("super+c", pid: 99)
        })
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in
            throw ComputerUseError.permissionDenied("Wrong target")
        }, send: { _, _ in sent += 1 }) {
            try InputSimulation.scrollTargeted(at: .zero, direction: "down", pages: 1, pid: 99)
        })
        XCTAssertEqual(sent, 0)
    }

    func testNestedOperationCannotReplaceTheActiveGuard() throws {
        var checked = false
        try NativeInputGuard.withValidation({ _ in checked = true }, send: { _, _ in }) {
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }, send: { _, _ in }) {})
            try NativeInputGuard.validate(pid: 42)
        }
        XCTAssertTrue(checked)
    }

    func testGlobalInputRefusesAnotherAppBeforeMovingThePointer() {
        var sent = false
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in
            guard pid == 42 else { throw ComputerUseError.permissionDenied("Wrong app") }
        }, send: { _, _ in sent = true }, hitTest: { point in
            XCTAssertEqual(point, CGPoint(x: 100, y: 120))
            return 99
        }, sendGlobal: { _ in sent = true }) {
            try InputSimulation.clickGlobally(at: CGPoint(x: 100, y: 120), button: .left, clickCount: 1)
        })
        XCTAssertFalse(sent)
    }

    func testGlobalEventsRecheckTheHitTargetThroughoutTheSequence() {
        var hitTests = 0
        var sent = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ pid in
            guard pid == 42 else { throw ComputerUseError.permissionDenied("Window changed") }
        }, hitTest: { _ in
            hitTests += 1
            return hitTests < 3 ? 42 : 99
        }, sendGlobal: { _ in sent += 1 }) {
            try InputSimulation.clickGlobally(at: CGPoint(x: 100, y: 120), button: .left, clickCount: 2)
        })
        XCTAssertEqual(hitTests, 4) // cleanup also refuses the changed global target
        XCTAssertEqual(sent, 2)
    }

    func testAccessibilityMutationChecksTheElementOwnerAndStopsAfterChange() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var changed = false
        var sent = 0
        try NativeInputGuard.withValidation({ target in
            XCTAssertEqual(target, pid)
            if changed { throw ComputerUseError.permissionDenied("App changed") }
        }, send: { _, _ in XCTFail("AX work must not post keyboard or pointer events") }) {
            XCTAssertEqual(try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                sent += 1
                changed = true
                return .success
            }), .success)
            XCTAssertThrowsError(try NativeInputGuard.setAttribute(element, kAXValueAttribute as CFString, "text" as CFString, send: { _, _, _ in
                sent += 1
                return .success
            }))
        }
        XCTAssertEqual(sent, 1)
    }

    func testChangedControlAfterAppValidationPreventsAccessibilityDispatch() throws {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let observed = ElementIdentityEvidence(attributes: [kAXRoleAttribute: "AXButton", kAXTitleAttribute: "Save"])
        var current = observed
        var sent = 0
        let review = {
            try ElementIdentityEvidence.requireCurrent(observed) { current }
        }
        try NativeInputGuard.withValidation({ _ in
            current = ElementIdentityEvidence(attributes: [kAXRoleAttribute: "AXButton", kAXTitleAttribute: "Delete"])
        }) {
            XCTAssertThrowsError(try NativeInputGuard.performAction(element, kAXPressAction as CFString, revalidateTarget: review, send: { _, _ in
                sent += 1
                return .success
            }))
            XCTAssertThrowsError(try NativeInputGuard.setAttribute(element, kAXValueAttribute as CFString, "text" as CFString, revalidateTarget: review, send: { _, _, _ in
                sent += 1
                return .success
            }))
        }
        XCTAssertEqual(sent, 0)
    }

    func testRepeatedAccessibilityActionsStopWhenTheFirstActionRecyclesTheControl() throws {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let observed = ElementIdentityEvidence(attributes: [kAXRoleAttribute: "AXButton", kAXTitleAttribute: "Open"])
        var current: ElementIdentityEvidence? = observed
        var sent = 0
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }) {
            for _ in 0..<2 {
                _ = try NativeInputGuard.performAction(element, kAXPressAction as CFString, revalidateTarget: {
                    try ElementIdentityEvidence.requireCurrent(observed) { current }
                }, send: { _, _ in
                    sent += 1
                    current = nil
                    return .success
                })
            }
        })
        XCTAssertEqual(sent, 1)
    }

    func testControlReviewIsDispatchScopedAndCancellationStillFencesTheWrite() throws {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let cancellation = NativeOperationCancellation()
        var reviewed = 0
        var sent = 0
        try NativeInputGuard.withValidation({ _ in }, cancellation: cancellation) {
            XCTAssertEqual(try NativeInputGuard.performAction(element, kAXPressAction as CFString, revalidateTarget: {
                reviewed += 1
            }, send: { _, _ in
                sent += 1
                return .success
            }), .success)
            // Ordinary post-action inspection must not rerun a consumed review.
            try NativeInputGuard.validate(element: element)
            XCTAssertEqual(reviewed, 1)
            XCTAssertThrowsError(try NativeInputGuard.setAttribute(element, kAXValueAttribute as CFString, "text" as CFString, revalidateTarget: {
                reviewed += 1
                cancellation.cancel()
            }, send: { _, _, _ in
                sent += 1
                return .success
            }))
        }
        XCTAssertEqual(reviewed, 2)
        XCTAssertEqual(sent, 1)
    }

    func testUncertainAccessibilityResultsNeverReachAnAlternateInputPath() throws {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        for result in [AXError.failure, .cannotComplete, .invalidUIElement] {
            var primarySends = 0
            var fallbackSends = 0
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }) {
                _ = try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                    primarySends += 1
                    return result
                })
                fallbackSends += 1
            })
            XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in }) {
                _ = try NativeInputGuard.setAttribute(element, kAXValueAttribute as CFString, "text" as CFString, send: { _, _, _ in
                    primarySends += 1
                    return result
                })
                fallbackSends += 1
            })
            XCTAssertEqual(primarySends, 2)
            XCTAssertEqual(fallbackSends, 0)
        }
    }

    func testExplicitlyUnsupportedAccessibilityActionsRemainAvailableForFallback() throws {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        try NativeInputGuard.withValidation({ _ in }) {
            XCTAssertEqual(try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in .actionUnsupported }), .actionUnsupported)
            XCTAssertEqual(try NativeInputGuard.setAttribute(element, kAXValueAttribute as CFString, "text" as CFString, send: { _, _, _ in .attributeUnsupported }), .attributeUnsupported)
        }
    }

    func testAccessibilityRejectionThrowsInsteadOfInvitingAnInputFallback() {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var sent = false
        XCTAssertThrowsError(try NativeInputGuard.withValidation({ _ in
            throw ComputerUseError.permissionDenied("Wrong app")
        }, send: { _, _ in sent = true }) {
            _ = try NativeInputGuard.performAction(element, kAXPressAction as CFString, send: { _, _ in
                sent = true
                return .actionUnsupported
            })
            // The caller never reaches its fallback after a failed guard.
            sent = true
        })
        XCTAssertFalse(sent)
    }
}
