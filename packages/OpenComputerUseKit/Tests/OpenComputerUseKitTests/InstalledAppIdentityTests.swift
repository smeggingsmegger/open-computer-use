import Foundation
import XCTest
@testable import OpenComputerUseKit

final class InstalledAppIdentityTests: XCTestCase {
    func testDistinctAppCopiesRemainAmbiguousAndAliasesDeduplicate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeApp(root.appendingPathComponent("One/Example.app"))
        let second = try makeApp(root.appendingPathComponent("Two/Example.app"))
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let single = try AppIdentityResolver.resolveCandidates([first, alias, first])
        XCTAssertEqual(single.status, "resolved")
        XCTAssertEqual(single.candidates.count, 1)
        XCTAssertNotEqual(single.candidates[0].signing.status, "valid_signature")
        let ambiguous = try AppIdentityResolver.resolveCandidates([first, second])
        XCTAssertEqual(ambiguous.status, "ambiguous")
        XCTAssertEqual(ambiguous.candidates.count, 2)
        XCTAssertNotEqual(ambiguous.candidates[0].bundlePath, ambiguous.candidates[1].bundlePath)
        XCTAssertEqual(try AppIdentityResolver.resolveCandidates([]).status, "not_found")
    }

    func testExactPathMetadataDoesNotExecuteTheAppAndUsesStructuredKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root.appendingPathComponent("Example.app"))
        let server = StdioMCPServer()
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "taffy/app-identity", "params": ["query": app.path]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let response = try XCTUnwrap(server.handle(line: line))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        XCTAssertEqual(result["version"] as? Int, 1)
        XCTAssertEqual(result["status"] as? String, "resolved")
        let identities = try XCTUnwrap(result["candidates"] as? [[String: Any]])
        XCTAssertEqual(identities.first?["bundle_identifier"] as? String, "test.identity.fixture")
        XCTAssertNotNil(identities.first?["executable_path"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ran").path))
    }

    func testIdentityCapabilitiesAreSeparateFromProviderTools() throws {
        let server = StdioMCPServer()
        let response = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#))
        XCTAssertTrue(response.contains("taffy/appIdentityMetadata"))
        XCTAssertTrue(response.contains("taffy/appBoundOperations"))
        let tools = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        XCTAssertFalse(tools.contains("taffy/app-call"))
        XCTAssertFalse(tools.contains("taffy/app-identity"))
        let invalid = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"taffy/app-identity","params":{"query":"ignored","allow":true}}"#))
        XCTAssertTrue(invalid.contains(#""isError":true"#))
    }

    func testRealSystemCodeSignatureMetadataIsVerifiedOffline() {
        let signing = AppSigningMetadata.inspect(URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertEqual(signing.status, "valid_signature")
        XCTAssertFalse(signing.designatedRequirement?.isEmpty ?? true)
        XCTAssertFalse(signing.codeDirectoryHash?.isEmpty ?? true)
    }

    private func makeApp(_ url: URL) throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.identity.fixture", "CFBundleName": "Example", "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        // A visible failure marker if metadata lookup ever executes this fixture.
        try Data("#!/bin/sh\ntouch \"$(dirname \"$0\")/../../../ran\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return url
    }
}
