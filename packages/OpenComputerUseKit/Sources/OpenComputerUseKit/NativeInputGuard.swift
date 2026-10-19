import Foundation
import CoreGraphics
import ApplicationServices

/// The stdio service executes each operation synchronously on one thread.
/// Keep its identity guard scoped there, including low-level input helpers.
enum NativeInputGuard {
    private static let key = "taffy.native-input-identity"

    private final class Scope {
        let validate: (pid_t) throws -> Void
        let send: (CGEvent, pid_t) -> Void
        let hitTest: (CGPoint) throws -> pid_t
        let sendGlobal: (CGEvent) -> Void
        let cancellation: NativeOperationCancellation?
        let held = NativeHeldInput()
        var keyboardTargetReview: (() throws -> Void)?
        var mouseTargetReview: (() throws -> Void)?
        var accessibilityTargetReview: (() throws -> Void)?

        init(validate: @escaping (pid_t) throws -> Void, send: @escaping (CGEvent, pid_t) -> Void,
             hitTest: @escaping (CGPoint) throws -> pid_t, sendGlobal: @escaping (CGEvent) -> Void,
             cancellation: NativeOperationCancellation?) {
            self.validate = validate
            self.send = send
            self.hitTest = hitTest
            self.sendGlobal = sendGlobal
            self.cancellation = cancellation
        }
    }

    static func withValidation<T>(
        _ validate: @escaping (pid_t) throws -> Void,
        send: @escaping (CGEvent, pid_t) -> Void = { event, pid in event.postToPid(pid) },
        hitTest: @escaping (CGPoint) throws -> pid_t = globalPointerTarget,
        sendGlobal: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        cancellation: NativeOperationCancellation? = nil,
        operation: () throws -> T
    ) throws -> T {
        let dictionary = Thread.current.threadDictionary
        guard dictionary[key] == nil else {
            throw ComputerUseError.stateUnavailable("An input identity guard is already active.")
        }
        try cancellation?.check()
        let scope = Scope(validate: validate, send: send, hitTest: hitTest, sendGlobal: sendGlobal, cancellation: cancellation)
        dictionary[key] = scope
        defer { dictionary.removeObject(forKey: key) }
        let outcome = Result { try operation() }
        // Cancellation fences ordinary input, but release-only cleanup must
        // still revalidate the original target independently of that token.
        guard scope.held.release(validate: validate, hitTest: hitTest) else {
            throw ComputerUseError.stateUnavailable("Native held-input cleanup could not be completed for the original target. Input state is uncertain; stop and inspect the app before continuing.")
        }
        return try outcome.get()
    }

    // Review each new key-down, but allow key-up and held-input cleanup even
    // when typing itself changed focus. Never retain this review for snapshots.
    static func withKeyboardTargetReview<T>(_ review: @escaping () throws -> Void,
                                            operation: () throws -> T) throws -> T {
        guard let scope = Thread.current.threadDictionary[key] as? Scope else {
            try validate(pid: 0)
            return try operation()
        }
        let previous = scope.keyboardTargetReview
        scope.keyboardTargetReview = review
        defer { scope.keyboardTargetReview = previous }
        try review()
        try scope.cancellation?.check()
        return try operation()
    }

    static func validate(pid: pid_t) throws {
        if let scope = Thread.current.threadDictionary[key] as? Scope {
            try scope.cancellation?.check()
            try scope.validate(pid)
            try scope.cancellation?.check()
        } else if bindingRequired {
            throw ComputerUseError.permissionDenied("The required input identity guard is missing. Restart the operation through the app-bound helper transport.")
        }
    }

    // Recheck before every click-down, including a double-click's second down.
    // Releases must still reach the original app when a click changes the UI.
    static func withMouseTargetReview<T>(_ review: @escaping () throws -> Void,
                                         operation: () throws -> T) throws -> T {
        guard let scope = Thread.current.threadDictionary[key] as? Scope else {
            try validate(pid: 0)
            return try operation()
        }
        let previous = scope.mouseTargetReview
        scope.mouseTargetReview = review
        defer { scope.mouseTargetReview = previous }
        try review()
        try scope.cancellation?.check()
        return try operation()
    }

    private static func reviewMouseDown(_ event: CGEvent, scope: Scope) throws {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            try scope.mouseTargetReview?()
        default:
            break
        }
    }

    // A fallback may act on a child/row of the requested control. Keep checking
    // the original target as well as that candidate at the actual AX dispatch.
    static func withAccessibilityTargetReview<T>(_ review: @escaping () throws -> Void,
                                                 operation: () throws -> T) throws -> T {
        guard let scope = Thread.current.threadDictionary[key] as? Scope else {
            try validate(pid: 0)
            return try operation()
        }
        let previous = scope.accessibilityTargetReview
        scope.accessibilityTargetReview = {
            try previous?()
            try review()
        }
        defer { scope.accessibilityTargetReview = previous }
        try scope.accessibilityTargetReview?()
        try scope.cancellation?.check()
        return try operation()
    }

    static var isActive: Bool { Thread.current.threadDictionary[key] != nil }
    static var bindingRequired: Bool { ProcessInfo.processInfo.environment["TAFFY_REQUIRE_APP_IDENTITY"] == "1" }

    static func validate(element: AXUIElement) throws {
        guard isActive else { try validate(pid: 0); return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else {
            throw ComputerUseError.permissionDenied("The accessibility target cannot be verified. Inspect the approved app again.")
        }
        try validate(pid: pid)
    }

    static func performAction(_ element: AXUIElement, _ action: CFString,
                              revalidateTarget: () throws -> Void = {},
                              send: (AXUIElement, CFString) -> AXError = { AXUIElementPerformAction($0, $1) }) throws -> AXError {
        try validate(element: element)
        try (Thread.current.threadDictionary[key] as? Scope)?.accessibilityTargetReview?()
        try revalidateTarget()
        try (Thread.current.threadDictionary[key] as? Scope)?.cancellation?.check()
        return try checkedAccessibilityResult(send(element, action))
    }

    static func setAttribute(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef,
                             revalidateTarget: () throws -> Void = {},
                             send: (AXUIElement, CFString, CFTypeRef) -> AXError = { AXUIElementSetAttributeValue($0, $1, $2) }) throws -> AXError {
        try validate(element: element)
        try (Thread.current.threadDictionary[key] as? Scope)?.accessibilityTargetReview?()
        try revalidateTarget()
        try (Thread.current.threadDictionary[key] as? Scope)?.cancellation?.check()
        return try checkedAccessibilityResult(send(element, attribute, value))
    }

    private static func checkedAccessibilityResult(_ result: AXError) throws -> AXError {
        // AX timeouts and generic failures do not prove that a mutation failed
        // to reach the app. Returning false upstream would invite another click
        // path or append the same text with keyboard input.
        if isActive {
            switch result {
            case .failure, .cannotComplete:
                throw ComputerUseError.stateUnavailable("The Accessibility action returned an uncertain result. Do not repeat it or switch input methods. Run get_app_state and verify whether the action happened before continuing.")
            case .invalidUIElement:
                throw ComputerUseError.stateUnavailable("The Accessibility target disappeared during the action. Run get_app_state and verify the current result before acting again.")
            default:
                break
            }
        }
        return result
    }

    static func post(_ event: CGEvent, pid: pid_t,
                     sendUnbound: (CGEvent, pid_t) -> Void = { event, pid in event.postToPid(pid) }) throws {
        if let scope = Thread.current.threadDictionary[key] as? Scope {
            try scope.cancellation?.check()
            try scope.validate(pid)
            if event.type == .keyDown { try scope.keyboardTargetReview?() }
            try reviewMouseDown(event, scope: scope)
            try scope.cancellation?.check()
            try scope.held.record(event, pid: pid, route: .targeted, send: { scope.send($0, pid) })
            scope.send(event, pid)
        } else {
            try validate(pid: pid)
            sendUnbound(event, pid)
        }
    }

    static func postPrivate(_ event: CGEvent, pid: pid_t, send: @escaping (CGEvent, pid_t) -> Void) throws {
        try validate(pid: pid)
        if let scope = Thread.current.threadDictionary[key] as? Scope {
            try reviewMouseDown(event, scope: scope)
            try scope.cancellation?.check()
            try scope.held.record(event, pid: pid, route: .privateTargeted, send: { send($0, pid) })
        }
        send(event, pid)
    }

    static func postGlobal(_ event: CGEvent,
                           sendUnbound: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) throws {
        if let scope = Thread.current.threadDictionary[key] as? Scope {
            try scope.cancellation?.check()
            let pid = try scope.hitTest(event.location)
            try scope.validate(pid)
            try reviewMouseDown(event, scope: scope)
            try scope.cancellation?.check()
            try scope.held.record(event, pid: pid, route: .global, send: scope.sendGlobal)
            scope.sendGlobal(event)
        } else {
            try validate(pid: 0)
            sendUnbound(event)
        }
    }

    private static func globalPointerTarget(_ point: CGPoint) throws -> pid_t {
        guard point.x.isFinite, point.y.isFinite, Float(point.x).isFinite, Float(point.y).isFinite else {
            throw ComputerUseError.invalidArguments("Global input needs finite screen coordinates.")
        }
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        var pid: pid_t = 0
        guard result == .success, let element, AXUIElementGetPid(element, &pid) == .success, pid > 0 else {
            throw ComputerUseError.permissionDenied("The app under the pointer cannot be verified. Keep the approved window visible or use app-targeted input.")
        }
        return pid
    }
}
