import CoreGraphics
import Foundation

/// Thread-confined ledger of submitted input, separated by delivery path.
/// Posting success is not proof of WindowServer delivery.
final class NativeHeldInput {
    enum Route: Hashable { case targeted, privateTargeted, global }
    private struct Target: Hashable { let route: Route; let pid: pid_t }
    private struct Key: Equatable { let route: Route; let pid: pid_t; let kind: Int; let code: Int64 }
    private struct Held { let key: Key; var event: CGEvent; let releaseType: CGEventType; let send: (CGEvent) -> Void }
    private var held: [Held] = []
    private var flags: [Target: CGEventFlags] = [:]

    private func modifier(_ code: Int64) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    func record(_ event: CGEvent, pid: pid_t, route: Route, send: @escaping (CGEvent) -> Void) throws {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let key: Key
        let release: CGEventType
        let down: Bool
        switch event.type {
        case .keyDown, .keyUp:
            key = Key(route: route, pid: pid, kind: 0, code: code)
            release = .keyUp; down = event.type == .keyDown
            flags[Target(route: route, pid: pid)] = event.flags
        case .flagsChanged:
            guard let flag = modifier(code) else { return }
            key = Key(route: route, pid: pid, kind: 0, code: code)
            release = .flagsChanged; down = event.flags.contains(flag)
            flags[Target(route: route, pid: pid)] = event.flags
        case .leftMouseDown, .leftMouseUp:
            key = Key(route: route, pid: pid, kind: 1, code: 0)
            release = .leftMouseUp; down = event.type == .leftMouseDown
        case .rightMouseDown, .rightMouseUp:
            key = Key(route: route, pid: pid, kind: 1, code: 1)
            release = .rightMouseUp; down = event.type == .rightMouseDown
        case .otherMouseDown, .otherMouseUp:
            key = Key(route: route, pid: pid, kind: 1, code: event.getIntegerValueField(.mouseEventButtonNumber))
            release = .otherMouseUp; down = event.type == .otherMouseDown
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let button: Int64 = event.type == .leftMouseDragged ? 0 : event.type == .rightMouseDragged ? 1 : event.getIntegerValueField(.mouseEventButtonNumber)
            if let index = held.firstIndex(where: { $0.key == Key(route: route, pid: pid, kind: 1, code: button) }) {
                guard let copy = event.copy() else {
                    throw ComputerUseError.stateUnavailable("Native drag tracking failed; no additional motion was sent. Inspect the app before continuing.")
                }
                held[index].event = copy
            }
            return
        default: return
        }
        if !down { held.removeAll { $0.key == key }; return }
        guard held.count < 64, let copy = event.copy() else {
            throw ComputerUseError.stateUnavailable("Native held-input tracking limit reached; no additional input was sent.")
        }
        if let index = held.firstIndex(where: { $0.key == key }) { held[index].event = copy }
        else { held.append(Held(key: key, event: copy, releaseType: release, send: send)) }
    }

    func release(validate: (pid_t) throws -> Void, hitTest: (CGPoint) throws -> pid_t) -> Bool {
        var submitted = true
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        for item in held.reversed() {
            do {
                guard ProcessInfo.processInfo.systemUptime < deadline else { submitted = false; break }
                if item.key.route == .global, try hitTest(item.event.location) != item.key.pid {
                    submitted = false; continue
                }
                try validate(item.key.pid)
                guard ProcessInfo.processInfo.systemUptime < deadline else { submitted = false; break }
                guard let up = item.event.copy() else { submitted = false; continue }
                up.type = item.releaseType
                if item.key.kind == 0 {
                    let target = Target(route: item.key.route, pid: item.key.pid)
                    var remaining = flags[target] ?? up.flags
                    if let flag = modifier(item.key.code) { remaining.remove(flag) }
                    flags[target] = remaining
                    up.flags = remaining
                }
                item.send(up)
            } catch { submitted = false }
        }
        held.removeAll()
        return submitted
    }
}
