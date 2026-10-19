# Cached native snapshot process binding

The host needs app authorization to match the app actually receiving input.
This change implements snapshot lifetime checking as one prerequisite; it does
not implement stable signed app approval or its host transport contract.

- Running app descriptors capture kernel PID/start-time/executable-path evidence.
- The service requires explicit get_app_state before input instead of silently
  capturing state during an input call.
- Cached state is checked against current process metadata before it is returned
  to an input operation. An exited or changed process clears every cached alias.
- Post-action capture stays on the inspected process instead of resolving or
  relaunching by name. Only explicit get_app_state resolves a new target.
- Tests cover identity changes/missing evidence, alias invalidation, all seven
  input entry points without inspection, and the test process's real metadata.
- AppKit-only lifetime evidence failed the real-process regression. Kernel
  proc_pidinfo/proc_pidpath replaced it; the regression now passes.

Validation: Swift suite ran 171 tests, one skipped, no failures. OpenComputerUse
build passed. GUI restart, focus, and final per-event race acceptance are not
established by unit tests. The check is at input-operation entry, not a promise
that an app cannot exit between the check and an event delivery. Stable signer
validation, helper identity negotiation, and Windows/Linux parity remain work.
