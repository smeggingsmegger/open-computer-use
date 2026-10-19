# Native cancellation guard foundation

The user requested quiet, capable bots with reliable Stop behavior. Added an
irreversible thread-safe operation token and optional checks at the existing
identity-guard boundaries. Inert-sink tests cover cancellation from another
thread, cancellation during validation, and independence of later operations.

Affected sources: `NativeOperationCancellation.swift`, `NativeInputGuard.swift`,
and `NativeInputGuardTests.swift` in the kit. The active native-cancellation
execution plan records the remaining transport, held-input tracking, cleanup,
host negotiation, and native acceptance requirements. This foundation alone
does not change the current host Stop behavior or advertise stronger guarantees.

Validation: `swift test --filter NativeInputGuardTests` passed all 13 tests.
No GUI or OS input is used by the new tests.

Follow-up: required-binding stdio execution now keeps its reader responsive
while one app-bound action executes on a serial queue. Private cancellation
matches the original request ID, cancels its token, and permanently fences the
lane. Extra input is rejected rather than queued; EOF cancels active work and
has a bounded drain. Standalone and direct app-agent calls remain synchronous.
No stronger capability is advertised and the embedding host does not use this
path until cleanup is implemented. Pipe-level and native verification remain.

Guard and request-lane verification passed all 15 selected Swift tests.

The production transport loop now has an internal I/O seam for real-pipe tests.
The test keeps stdin open while a bound executor is blocked, checks that the
reader handles matching cancellation, distinguishes numeric and string request
IDs, and rejects additional actions without executing them. Event sinks remain
inert. The acknowledgment explicitly reports requested cancellation and no
cleanup confirmation. This verifies transport routing, not OS delivery.

All 16 selected guard, lane, and pipe tests pass.

Held-input follow-up: the guard now tracks submitted downs separately for public,
private SkyLight, and global delivery. On scope exit it submits releases in
reverse order with remaining modifier flags, revalidating original identity.
Global cleanup checks the latest submitted drag position; a changed target
refuses release with an uncertain-state error. Tracking is bounded to 64 downs,
and cleanup checks a half-second budget around validation. A blocked OS call
still requires host termination. Failed drag-event copying refuses further
motion rather than retaining an obsolete cleanup position.

All 19 selected guard, held-input, lane, and real-pipe tests pass with inert
sinks. A full Swift-suite attempt was rejected by automatic approval review
because that suite includes live Chrome/desktop-input tests and the native-test
hold remains active. No GUI was launched by this verification. Host negotiation,
helper staging, and actual OS cleanup acceptance remain outstanding.

Host integration follow-up: required-binding stdio now advertises operation
cancellation version 1. Direct/synchronous handlers do not advertise it. The
embedding host keeps the operation future alive during a bounded cancellation
notification and cleanup grace, then terminates the helper under its existing
exit-confirmed control lease. Cancellation is not treated as completion or OS
cleanup confirmation. The 20 inert Swift tests pass, including capability
scope; the host fixture verifies targeted notification, session fencing, and
termination fallback. Staging and native acceptance remain open.
