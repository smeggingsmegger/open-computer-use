import Foundation

let computerUseServerInstructions = """
Computer Use tools let you interact with macOS apps by performing UI actions.

Some apps might have a separate dedicated plugin or skill. You may want to use that plugin or skill instead of Computer Use when it seems like a good fit for the task. While the separate plugin or skill may not expose every feature in the app, if the plugin can perform the task with its available features, prefer it. If the needed capability is not exposed there, use Computer Use may be appropriate for the missing interaction.

Begin by calling `get_app_state` every turn you want to use Computer Use to get the latest state before acting. Codex will automatically stop the session after each assistant turn, so this step is required before interacting with apps in a new assistant turn.

The available tools are list_apps, get_app_state, click, perform_secondary_action, scroll, drag, type_text, press_key, and set_value. If any of these are not available in your environment, use tool_search to surface one before calling any Computer Use action tools.

Computer Use tools allow you to use the user's apps in the background, so while you're using an app, the user can continue to use other apps on their computer. Avoid doing anything that would disrupt the user's active session, such as overwriting the contents of their clipboard, unless they asked you to!

After each action, use the action result or fetch the latest state to verify the UI changed as expected.
Prefer element-targeted interactions over coordinate clicks when an index for the targeted element is available. Note that element indices are the sequential integers from the app state's accessibility tree.
Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks.
Ask the user before taking destructive or externally visible actions such as sending, deleting, or purchasing. If helpful, you can ask follow-up questions before taking action to make sure you’re understanding the user’s request correctly.
"""

// In run(), the lane prevents concurrent dispatcher access. Only cancellation
// and locked output cross threads; direct handle callers remain serialized.
public final class StdioMCPServer: @unchecked Sendable {
    private let dispatcher: ComputerUseToolDispatcher
    private let requireAppIdentity: Bool
    private let lane = NativeRequestLane()
    private let outputLock = NSLock()

    private func writeResponse(_ response: String?) {
        guard let response else { return }
        outputLock.lock()
        defer { outputLock.unlock() }
        FileHandle.standardOutput.write(Data((response + "\n").utf8))
    }

    private func requestIdentity(_ value: Any?) -> String? {
        guard let value, value is String || (value is NSNumber && CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID()),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return data.base64EncodedString()
    }

    public init(service: ComputerUseService = ComputerUseService(), requireAppIdentity: Bool = ProcessInfo.processInfo.environment["TAFFY_REQUIRE_APP_IDENTITY"] == "1") {
        self.dispatcher = ComputerUseToolDispatcher(service: service)
        self.requireAppIdentity = requireAppIdentity
    }

    public func run() throws {
        try runTransport(read: { readLine(strippingNewline: true) },
                         writeResponse: { [self] in writeResponse($0) },
                         executeBound: { [self] in handle(line: $0, cancellation: $1) })
    }

    // Shared by production stdio and inert pipe tests. No alternate tool or
    // environment flag exposes the test executor to an external caller.
    func runTransport(read: () -> String?,
                      writeResponse: @escaping @Sendable (String?) -> Void,
                      executeBound: @escaping @Sendable (String, NativeOperationCancellation) -> String?) throws {
        let operations = DispatchQueue(label: "taffy.native-bound-operation")
        let pending = DispatchGroup()
        while let line = read() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if requireAppIdentity, let payload = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] {
                if payload["method"] as? String == "taffy/cancel-operation" {
                    guard let params = payload["params"] as? [String: Any], Set(params.keys) == ["request_id"], let id = requestIdentity(params["request_id"]) else {
                        writeResponse(try encodeJSONRPCError(id: payload["id"], code: -32602, message: "Cancellation requires only the original request_id."))
                        continue
                    }
                    let cancelled = lane.cancel(id: id)
                    if payload["id"] != nil { writeResponse(try encodeJSONRPCResult(id: payload["id"], result: ["cancellation_requested": cancelled, "cleanup_confirmed": false])) }
                    continue
                }
                if payload["method"] as? String == "taffy/app-call" {
                    guard let id = requestIdentity(payload["id"]) else {
                        writeResponse(try encodeJSONRPCError(id: nil, code: -32600, message: "App-bound operations require a string or numeric request ID."))
                        continue
                    }
                    guard let cancellation = lane.begin(id: id) else {
                        writeResponse(try encodeJSONRPCError(id: payload["id"], code: -32000, message: "Native input is busy or cancelled; no additional operation was queued."))
                        continue
                    }
                    pending.enter()
                    operations.async { [self] in
                        let response = executeBound(line, cancellation)
                        lane.finish(cancellation)
                        writeResponse(response)
                        pending.leave()
                    }
                    continue
                }
                if lane.unavailable {
                    writeResponse(try encodeJSONRPCError(id: payload["id"], code: -32000, message: "Native input is busy or cancelled; no additional operation was queued."))
                    continue
                }
            }
            writeResponse(handle(line: line, cancellation: nil, cancellableTransport: requireAppIdentity))
        }
        lane.close()
        // EOF cancels input. Do not wait indefinitely for an OS call to return;
        // the embedding host retains its process deadline and termination fence.
        _ = pending.wait(timeout: .now() + 5)
    }

    public func handle(line: String) -> String? {
        handle(line: line, cancellation: nil)
    }

    private func handle(line: String, cancellation: NativeOperationCancellation?, cancellableTransport: Bool = false) -> String? {
        do {
            guard let payload = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return try encodeJSONRPCError(id: nil, code: -32700, message: "Invalid JSON-RPC payload")
            }

            let method = payload["method"] as? String
            let id = payload["id"]
            let params = payload["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                var experimental = ["taffy/appIdentityMetadata": 1, "taffy/appBoundOperations": 1]
                if cancellableTransport { experimental["taffy/operationCancellation"] = 1 }
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "protocolVersion": "2025-03-26",
                        "serverInfo": [
                            "name": "open-computer-use",
                            "version": openComputerUseVersion,
                        ],
                        "capabilities": [
                            "experimental": experimental,
                            "tools": [
                                "listChanged": false,
                            ],
                        ],
                        "instructions": computerUseServerInstructions,
                    ]
                )
            case "notifications/initialized":
                return nil
            case "notifications/turn-ended":
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.reset()
                }
                return nil
            case "ping":
                return try encodeJSONRPCResult(id: id, result: [:])
            case "taffy/app-identity":
                guard Set(params.keys) == ["query"], let query = params["query"] as? String else {
                    throw ComputerUseError.invalidArguments("App identity lookup requires only a query string.")
                }
                return try encodeJSONRPCResult(id: id, result: AppIdentityResolver.resolve(query).asDictionary)
            case "taffy/app-call":
                guard Set(params.keys) == ["version", "identity", "name", "arguments"],
                      let version = params["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 1, version.doubleValue == 1,
                      let identity = params["identity"] as? [String: Any],
                      let name = params["name"] as? String,
                      let arguments = params["arguments"] as? [String: Any] else {
                    throw ComputerUseError.invalidArguments("App-bound calls require version 1, identity, name, and arguments.")
                }
                let result = try dispatcher.callBoundTool(name: name, arguments: arguments, identity: BoundAppIdentity.decode(identity), cancellation: cancellation)
                return try encodeJSONRPCResult(id: id, result: result.asDictionary)
            case "tools/list":
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "tools": ToolDefinitions.all.map(\.asDictionary),
                    ]
                )
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                if requireAppIdentity, name != "list_apps" {
                    throw ComputerUseError.permissionDenied("This host requires app-bound input; refresh helper capabilities and use the app-bound contract.")
                }
                let result = try dispatcher.callTool(name: name, arguments: arguments)
                return try encodeJSONRPCResult(
                    id: id,
                    result: result.asDictionary
                )
            default:
                if method == nil {
                    return nil
                }

                return try encodeJSONRPCError(id: id, code: -32601, message: "Method not found: \(method ?? "")")
            }
        } catch let error as ComputerUseError {
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let id = payload?["id"]
            let result = ToolCallResult.text(error.errorDescription ?? String(describing: error), isError: error.toolResultIsError)
            return try? encodeJSONRPCResult(id: id, result: result.asDictionary)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let id = payload?["id"]
            return try? encodeJSONRPCResult(
                id: id,
                result: [
                    "content": [
                        [
                            "type": "text",
                            "text": message,
                        ],
                    ],
                    "isError": true,
                ]
            )
        }
    }

    private func encodeJSONRPCResult(id: Any?, result: [String: Any]) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result,
        ])
    }

    private func encodeJSONRPCError(id: Any?, code: Int, message: String) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ])
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode JSON-RPC response.")
        }

        return text
    }
}
