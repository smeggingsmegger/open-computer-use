import Foundation

/// Shared by a transport reader and one serialized native operation. A token
/// is never reset or reused: later operations need a different token.
final class NativeOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let stopped = cancelled
        lock.unlock()
        if stopped {
            throw ComputerUseError.stateUnavailable("Native operation cancelled; no further input is permitted.")
        }
    }
}
