import Foundation
import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class NativeCancellationTransportTests: XCTestCase {
    private final class Results: @unchecked Sendable {
        let lock = NSLock()
        var responses: [String] = []
        var executions = 0
        var inputs: [CGEventType] = []
        func response(_ value: String) { lock.lock(); responses.append(value); lock.unlock() }
        func execution() { lock.lock(); executions += 1; lock.unlock() }
        func input(_ type: CGEventType) { lock.lock(); inputs.append(type); lock.unlock() }
    }

    func testCancellationIsAdvertisedOnlyByTheRequiredBindingReader() throws {
        let initialize = #"{"id":1,"method":"initialize"}"#
        func advertised(_ response: String) throws -> Bool {
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
            let result = value["result"] as? [String: Any]
            let capabilities = result?["capabilities"] as? [String: Any]
            let experimental = capabilities?["experimental"] as? [String: Any]
            return experimental?["taffy/operationCancellation"] as? Int == 1
        }
        for required in [false, true] {
            let server = StdioMCPServer(requireAppIdentity: required)
            XCTAssertFalse(try advertised(XCTUnwrap(server.handle(line: initialize))))
            let results = Results()
            var lines = [initialize].makeIterator()
            try server.runTransport(read: { lines.next() }, writeResponse: { response in
                if let response { results.response(response) }
            }, executeBound: { _, _ in XCTFail("Handshake must not execute input"); return nil })
            XCTAssertEqual(results.responses.count, 1)
            XCTAssertEqual(try advertised(XCTUnwrap(results.responses.first)), required)
        }
    }

    func testPipeReaderCancelsRunningInputAndRejectsAdditionalOperations() throws {
        let server = StdioMCPServer(requireAppIdentity: true)
        let pipe = Pipe()
        let started = DispatchSemaphore(value: 0)
        let cancelled = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        let writerDone = DispatchSemaphore(value: 0)
        let results = Results()
        Thread.detachNewThread {
            defer { try? pipe.fileHandleForWriting.close(); writerDone.signal() }
            pipe.fileHandleForWriting.write(Data("{\"id\":1,\"method\":\"taffy/app-call\"}\n".utf8))
            guard started.wait(timeout: .now() + 3) == .success else { return }
            let messages = [
                #"{"id":2,"method":"taffy/app-call"}"#,
                #"{"id":3,"method":"taffy/cancel-operation","params":{"request_id":"1"}}"#,
                #"{"id":4,"method":"taffy/cancel-operation","params":{"request_id":1}}"#,
                #"{"id":5,"method":"taffy/app-call"}"#,
            ]
            pipe.fileHandleForWriting.write(Data((messages.joined(separator: "\n") + "\n").utf8))
            // Keep stdin open until cancellation is acknowledged. EOF cannot
            // be the event that cancels the blocked action in this test.
            _ = cancelled.wait(timeout: .now() + 3)
            finish.signal()
        }
        try server.runTransport(read: {
            var bytes = Data()
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 1), !chunk.isEmpty {
                if chunk.first == 10 { return String(data: bytes, encoding: .utf8) }
                bytes.append(chunk)
            }
            return nil
        }, writeResponse: { response in
            guard let response else { return }
            results.response(response)
            if let value = (try? JSONSerialization.jsonObject(with: Data(response.utf8))) as? [String: Any], value["id"] as? Int == 4 {
                cancelled.signal()
            }
        }, executeBound: { _, token in
            results.execution()
            do {
                try NativeInputGuard.withValidation({ _ in }, send: { event, _ in results.input(event.type) }, cancellation: token) {
                    let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
                    try NativeInputGuard.post(down, pid: 42)
                    started.signal()
                    guard finish.wait(timeout: .now() + 3) == .success else { throw ComputerUseError.stateUnavailable("Test writer stalled") }
                    try NativeInputGuard.post(down, pid: 42)
                }
                return #"{"id":1,"result":"unexpected success"}"#
            } catch {
                return #"{"id":1,"error":{"message":"cancelled"}}"#
            }
        })
        XCTAssertEqual(writerDone.wait(timeout: .now() + 3), .success)
        results.lock.lock()
        let raw = results.responses
        let executions = results.executions
        let inputs = results.inputs
        results.lock.unlock()
        let responses = try raw.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(executions, 1)
        XCTAssertEqual(inputs, [.keyDown, .keyUp]) // no second down; cleanup alone is permitted
        XCTAssertEqual(responses.count, 5)
        XCTAssertEqual((responses.first { $0["id"] as? Int == 3 }?["result"] as? [String: Bool])?["cancellation_requested"], false)
        XCTAssertEqual((responses.first { $0["id"] as? Int == 4 }?["result"] as? [String: Bool])?["cancellation_requested"], true)
        XCTAssertEqual((responses.first { $0["id"] as? Int == 4 }?["result"] as? [String: Bool])?["cleanup_confirmed"], false)
        for id in [1, 2, 5] { XCTAssertNotNil(responses.first { $0["id"] as? Int == id }?["error"]) }
    }
}
