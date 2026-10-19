import AppKit
import XCTest
@testable import OpenComputerUseKit

final class DecisionObservationTests: XCTestCase {
    func testStructuredObservationUsesCaptureRecordsAndExcludesProtectedOrSyntheticText() throws {
        let input = ElementRecord(index: 1, identifier: "search", element: nil, localFrame: nil, role: "AXTextField", rawActions: [], prettyActions: [], decisionLabel: "Search")
        let password = ElementRecord(index: 2, identifier: "secret", element: nil, localFrame: nil, role: "AXSecureTextField", rawActions: [], prettyActions: [], decisionLabel: "Password")
        let synthetic = ElementRecord(index: 3, identifier: nil, element: nil, localFrame: nil, role: "AXStaticText", rawActions: [], prettyActions: [], isSyntheticText: true, decisionLabel: "Synthetic")
        let snapshot = AppSnapshot(
            app: RunningAppDescriptor(name: "Fixture", bundleIdentifier: "fixture.app", pid: NSRunningApplication.current.processIdentifier, runningApplication: .current),
            windowTitle: "Fixture", windowBounds: nil, targetWindowID: nil, targetWindowLayer: nil,
            screenshotPNGData: nil, mode: .accessibility, treeLines: ["private prose"], focusedSummary: nil,
            focusedElement: nil, focusedIdentity: nil, inputWindow: nil, inputWindowIdentity: nil,
            selectedText: "private selected text", elements: [1:input,2:password,3:synthetic]
        )
        let text = try XCTUnwrap(snapshot.decisionObservationJSON)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let observation = try XCTUnwrap(value["taffy_observation"] as? [String: Any])
        let elements = try XCTUnwrap(observation["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0]["name"] as? String, "Search")
        XCTAssertEqual(elements[0]["editable"] as? Bool, true)
        XCTAssertFalse(text.contains("private"))
        XCTAssertFalse(text.contains("Password"))
    }
}
