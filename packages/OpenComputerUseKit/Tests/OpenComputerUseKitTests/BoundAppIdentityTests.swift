import AppKit
import Foundation
import XCTest
@testable import OpenComputerUseKit

final class BoundAppIdentityTests: XCTestCase {
    func testRunningCodeMustMatchTheExactExpectedHash() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = try XCTUnwrap(SnapshotProcessIdentity.read(pid: pid).executablePath)
        let signing = AppSigningMetadata.inspect(URL(fileURLWithPath: path))
        XCTAssertNoThrow(try BoundAppIdentity.validateProcessCode(pid: pid, signing: signing))
        let wrong = AppSigningMetadata(status: signing.status, teamIdentifier: signing.teamIdentifier,
                                       designatedRequirement: signing.designatedRequirement,
                                       codeDirectoryHash: String(repeating: "0", count: 40))
        XCTAssertThrowsError(try BoundAppIdentity.validateProcessCode(pid: pid, signing: wrong))
    }

    func testUnverifiableAndMalformedCodeIdentitiesCannotCreateRequirements() {
        for signing in [
            AppSigningMetadata(status: "unsigned", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: String(repeating: "0", count: 40)),
            AppSigningMetadata(status: "valid_signature", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: "0\" or true"),
            AppSigningMetadata(status: "valid_signature", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: nil)
        ] {
            XCTAssertThrowsError(try BoundAppIdentity.codeRequirement(signing))
        }
    }

    func testRequiredBindingRefusesOrdinaryInputBeforeAppResolution() throws {
        let server = StdioMCPServer(requireAppIdentity: true)
        let response = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"press_key","arguments":{"app":"Never launch this","key":"Return"}}}"#))
        XCTAssertTrue(response.contains(#""isError":true"#))
        XCTAssertTrue(response.contains("requires app-bound input"))
    }

    func testBoundProtocolRejectsUnknownFieldsAndBooleanVersions() throws {
        let server = StdioMCPServer()
        for params in [
            #"{"version":true,"identity":{},"name":"press_key","arguments":{}}"#,
            #"{"version":1,"identity":{},"name":"press_key","arguments":{},"allow":true}"#
        ] {
            let response = try XCTUnwrap(server.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"taffy/app-call\",\"params\":\(params)}"))
            XCTAssertTrue(response.contains("App-bound calls require version 1"))
        }
        XCTAssertThrowsError(try BoundAppIdentity.decode(["platform": "macos", "allow": true]))
    }
}
