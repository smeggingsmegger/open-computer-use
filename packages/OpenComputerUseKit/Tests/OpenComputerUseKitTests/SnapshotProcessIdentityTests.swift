import AppKit
import XCTest
@testable import OpenComputerUseKit

final class SnapshotProcessIdentityTests: XCTestCase {
    func testCurrentProcessKernelMetadataMatchesWithoutInspectingWindows() {
        // Command-line XCTest need not be registered as an AppKit application:
        // NSRunningApplication.current can have PID -1 even while we are alive.
        let identity = SnapshotProcessIdentity.read(pid: getpid())
        XCTAssertNotNil(identity.launchedAt, "Missing kernel process-start evidence")
        XCTAssertNotNil(identity.executablePath, "Missing kernel executable evidence")
        XCTAssertTrue(identity.matches(SnapshotProcessIdentity.read(pid: getpid())))
        XCTAssertFalse(identity.matches(SnapshotProcessIdentity.read(pid: -1)))
    }

    func testAnInvalidAppDescriptorCannotUseTheCurrentProcessesIdentity() {
        let process = NSRunningApplication.current
        let wrongProcess = RunningAppDescriptor(name: "Unit test process", bundleIdentifier: process.bundleIdentifier, pid: -1, runningApplication: process)
        XCTAssertFalse(snapshotAppIsCurrent(wrongProcess))
    }

    func testProcessIncarnationRequiresCompleteMatchingEvidence() {
        let original = SnapshotProcessIdentity(pid: 10, launchedAt: Date(timeIntervalSince1970: 123), executablePath: "/Applications/Example.app/Contents/MacOS/Example")
        XCTAssertTrue(original.matches(original))
        XCTAssertFalse(original.matches(nil))
        for changed in [
            SnapshotProcessIdentity(pid: 11, launchedAt: original.launchedAt, executablePath: original.executablePath),
            SnapshotProcessIdentity(pid: 10, launchedAt: Date(timeIntervalSince1970: 124), executablePath: original.executablePath),
            SnapshotProcessIdentity(pid: 10, launchedAt: original.launchedAt, executablePath: "/another/Example"),
            SnapshotProcessIdentity(pid: 10, launchedAt: nil, executablePath: original.executablePath),
            SnapshotProcessIdentity(pid: 10, launchedAt: original.launchedAt, executablePath: nil)
        ] {
            XCTAssertFalse(original.matches(changed))
        }
        let incomplete = SnapshotProcessIdentity(pid: 10, launchedAt: nil, executablePath: nil)
        XCTAssertFalse(incomplete.matches(incomplete))
    }

    func testStaleProcessRemovesEverySnapshotAlias() throws {
        var cache = AppSnapshotCache()
        let snapshot = AppSnapshot(
            app: RunningAppDescriptor(name: "Example", bundleIdentifier: "example.app", pid: NSRunningApplication.current.processIdentifier, runningApplication: .current),
            windowTitle: nil, windowBounds: nil, targetWindowID: nil, targetWindowLayer: nil,
            screenshotPNGData: nil, mode: .accessibility, treeLines: [], focusedSummary: nil,
            focusedElement: nil, focusedIdentity: nil, inputWindow: nil, inputWindowIdentity: nil, selectedText: nil, elements: [:]
        )
        cache.store(snapshot, query: "Chosen alias")
        XCTAssertEqual(try cache.require("EXAMPLE", isCurrent: { _ in true }).app.name, "Example")
        XCTAssertThrowsError(try cache.require("Chosen alias", isCurrent: { _ in false }))
        for alias in ["Chosen alias", "Example", "example.app"] {
            XCTAssertThrowsError(try cache.require(alias, isCurrent: { _ in XCTFail("Stale alias retained"); return true }))
        }
        cache.store(snapshot, query: "Chosen alias")
        XCTAssertEqual(try cache.require("example.app", isCurrent: { _ in true }).app.name, "Example")
    }

    func testEveryInputRequiresExplicitInspectionWithoutResolvingOrLaunchingAnApp() {
        let service = ComputerUseService()
        let app = "No inspected app"
        let actions: [() throws -> ToolCallResult] = [
            { try service.click(app: app, elementIndex: "1", x: nil, y: nil, clickCount: 1, mouseButton: "left") },
            { try service.performSecondaryAction(app: app, elementIndex: "1", action: "Press") },
            { try service.scroll(app: app, direction: "down", elementIndex: "1", pages: 1) },
            { try service.drag(app: app, fromX: 0, fromY: 0, toX: 1, toY: 1) },
            { try service.typeText(app: app, text: "test") },
            { try service.pressKey(app: app, key: "Return") },
            { try service.setValue(app: app, elementIndex: "1", value: "test") }
        ]
        for action in actions {
            XCTAssertThrowsError(try action()) { error in
                XCTAssertTrue(error.localizedDescription.contains("Call get_app_state"), "Unexpected error: \(error)")
            }
        }
    }
}
