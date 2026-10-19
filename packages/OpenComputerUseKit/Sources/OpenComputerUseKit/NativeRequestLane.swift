import Foundation

/// One in-flight bound operation. Cancellation permanently fences this lane;
/// the host must replace the helper before requesting more native input.
final class NativeRequestLane: @unchecked Sendable {
    private let lock = NSLock()
    private var active: (String, NativeOperationCancellation)?
    private var closed = false

    func begin(id: String) -> NativeOperationCancellation? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, active == nil else { return nil }
        let token = NativeOperationCancellation()
        active = (id, token)
        return token
    }

    func finish(_ token: NativeOperationCancellation) {
        lock.lock()
        defer { lock.unlock() }
        if active?.1 === token { active = nil }
    }

    var unavailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed || active != nil
    }

    func cancel(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let active, active.0 == id else { return false }
        closed = true
        active.1.cancel()
        return true
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        active?.1.cancel()
    }
}
