# Private app-bound operations

Added the native operation contract that the host will use after its own user
approval. Host grants are not connected yet; standalone input remains unchanged
unless the host requests required binding.

- `taffy/app-call` version 1 requires an exact identity, tool name, and arguments.
  It rejects unknown fields/boolean versions and overrides the input app selector
  with the expected canonical bundle path. Only app inspection/input tools enter
  this contract; provider tool discovery is unchanged.
- The service validates the installed metadata against the expected object,
  confines the operation to that identity, and clears its context on return.
  Inspection chooses the exact installed copy, refuses multiple instances, and
  requests nonactivating launch of that path if no instance exists. No input
  call implicitly launches an app or bypasses explicit snapshot requirements.
- Cached/returned state validates process lifetime, bundle/executable paths, and
  running code with an exact code-directory-hash requirement. Unverifiable or
  unsigned code is refused by this version. This verifies code identity, not
  consequential effects or user consent.
- `TAFFY_REQUIRE_APP_IDENTITY=1` makes ordinary MCP input refuse; app-bound
  operations have their own advertised capability. The host must negotiate it
  before enabling this mode and must never fall back after refusal.
- Tests cover real running-code acceptance and wrong-hash refusal, malformed
  identities, required-binding refusal before app lookup, exact protocol fields,
  and separation from provider tools. Use the kernel process ID in that test;
  AppKit current-app registration was not ready at the first test entry.

Validation: Swift ran 179 tests, one skipped, zero failures. This version checks
identity at operation entry and snapshot capture, not every emitted event in a
long action. Native success/focus/launch acceptance, per-event checks, host
integration, separate saved grants, and platform parity remain unfinished.

The exact-code requirement follows Apple's
[Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
# Per-event enforcement follow-up

Added `NativeInputGuard` around bound operations. The inspected process and its
code identity are revalidated immediately before each targeted CGEvent/SkyLight
dispatch and AX mutation. Guard failures throw before input fallback. Snapshot
recovery checks its target before activating or changing attributes and avoids
bundle-name relaunch during a bound operation.

Six new tests use inert dispatch sinks to exercise typing/dragging interruption,
wrong targets, nested guards, and AX failures without native UI interaction.
Swift suite: 185 tests, one skipped, zero failures. Global pointer targeting,
SkyLight focus mutation, held-input cleanup, and native acceptance remain open.

## Global targeting and keyboard release follow-up

Required-binding mode refuses missing thread scopes, including dispatch from a
different thread. Global pointer events verify the AX hit element belongs to the
approved process before each event. Synthetic target focus retains process
lifetime evidence and verifies the onscreen window owner before activation or
deactivation. The corresponding Swift run passed 190 tests, one skipped.

Completed shortcuts now remove each modifier from the event flags before its
release is dispatched. The new full shortcut-sequence test initially expected
keyDown/keyUp for modifiers; CoreGraphics emits flagsChanged for those keys.
After correcting that expectation, all 191 Swift tests passed, one skipped.
The test checks intermediate flags and an empty final flags value using an
inert event sink. This fixes normal completion; it does not establish cleanup
after interruption or native WindowServer delivery. Those remain required.
