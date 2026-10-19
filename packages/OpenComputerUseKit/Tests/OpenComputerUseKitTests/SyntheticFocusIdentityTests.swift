import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

final class SyntheticFocusIdentityTests: XCTestCase {
    func testFocusTargetRequiresTheSameProcessAndWindowOwner() {
        let identity = SnapshotProcessIdentity(pid: 42, launchedAt: Date(timeIntervalSince1970: 100), executablePath: "/fixture/app")
        let window: [String: Any] = [kCGWindowNumber as String: NSNumber(value: 7), kCGWindowOwnerPID as String: NSNumber(value: 42), kCGWindowIsOnscreen as String: true]
        XCTAssertTrue(skyLightFocusTargetIsCurrent(identity: identity, current: identity, windowID: 7, windowInfo: [window]))
        let restarted = SnapshotProcessIdentity(pid: 42, launchedAt: Date(timeIntervalSince1970: 101), executablePath: "/fixture/app")
        XCTAssertFalse(skyLightFocusTargetIsCurrent(identity: identity, current: restarted, windowID: 7, windowInfo: [window]))
        var reassigned = window
        reassigned[kCGWindowOwnerPID as String] = NSNumber(value: 99)
        XCTAssertFalse(skyLightFocusTargetIsCurrent(identity: identity, current: identity, windowID: 7, windowInfo: [reassigned]))
        XCTAssertFalse(skyLightFocusTargetIsCurrent(identity: identity, current: identity, windowID: 7, windowInfo: []))
    }

    func testFocusCleanupRefusesAnExpiredProcessBeforePostingItsSavedRecord() {
        let context = SkyLightSyntheticFocusContext(
            deactivateTarget: SkyLightActivationCommand(psn: [UInt8](repeating: 0, count: 8), windowID: 0, focused: false),
            targetIdentity: SnapshotProcessIdentity(pid: 0, launchedAt: nil, executablePath: nil)
        )
        XCTAssertThrowsError(try SkyLightSPI.shared.endSyntheticTargetFocus(context)) { error in
            XCTAssertTrue(String(describing: error).contains("focus target changed"))
        }
    }
}
