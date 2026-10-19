import XCTest
import ApplicationServices
@testable import OpenComputerUseKit

final class ElementIdentityEvidenceTests: XCTestCase {
    func testLinkDestinationIsCapturedAcrossAXRepresentationsAndRevalidated() throws {
        func evidence(_ value: CFTypeRef?) -> ElementIdentityEvidence? {
            ElementIdentityEvidence.capture { name in
                switch name {
                case kAXRoleAttribute: return (.success, "AXLink" as CFString)
                case kAXTitleAttribute: return (.success, "Open report" as CFString)
                case kAXURLAttribute: return value == nil ? (.noValue, nil) : (.success, value)
                default: return (.attributeUnsupported, nil)
                }
            }
        }
        let original = "https://example.test/report" as CFString
        let observed = try XCTUnwrap(evidence(original))
        let url = try XCTUnwrap(URL(string: "https://example.test/report")) as NSURL
        XCTAssertEqual(observed, evidence(url))
        XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(observed) {
            evidence("https://example.test/delete" as CFString)
        })
        XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(observed) { evidence(nil) })
        XCTAssertNil(evidence(NSNumber(value: 7)))
        XCTAssertNil(evidence(String(repeating: "x", count: 4097) as CFString))
    }

    func testChangedControlIsRejectedBeforeAction() throws {
        let observed = ElementIdentityEvidence(attributes: ["AXRole": "AXButton", "AXTitle": "Preview"])
        XCTAssertNoThrow(try ElementIdentityEvidence.requireCurrent(observed) { observed })
        for attributes in [["AXRole": "AXButton", "AXTitle": "Send"],
                           ["AXRole": "AXTextField", "AXTitle": "Preview"],
                           ["AXRole": "AXButton", "AXTitle": "Preview", "AXIdentifier": "other"]] {
            XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(observed) {
                ElementIdentityEvidence(attributes: attributes)
            })
        }
    }

    func testUnavailableEvidenceNeverCountsAsAnUnchangedTarget() {
        let observed = ElementIdentityEvidence(attributes: ["AXRole": "AXButton"])
        XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(observed) { nil })
        XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(nil) { observed })
        XCTAssertThrowsError(try ElementIdentityEvidence.requireCurrent(nil) { nil })
    }
}
