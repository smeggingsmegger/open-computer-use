# Structured app identity contract

Status: in progress. Build a private, versioned host/helper contract for app
identity resolution and bound input. Metadata support alone confers no authority.

1. Resolve exact installed/running app candidates without launching, focusing,
   reading windows, or triggering permissions. Include canonical paths and
   independently checked code-signing metadata. Refuse ambiguous selection.
2. Negotiate metadata and bound-input support separately. Never let an older
   helper silently accept unknown expected-identity fields and act unbound.
3. Enforce expected identity in native execution, including captured snapshots.
4. Connect host task/saved grants using a separate versioned storage table;
   legacy name grants are preserved but not automatically promoted.
5. Test transport, ambiguity, replacement, stale identity, downgrade, and native
   app control. Windows/Linux need equivalent evidence and explicit negotiation.

This phase implements metadata only. No provider-facing tool or grant is added.

Metadata phase implemented: private RPC, canonical candidate resolution, offline
signature information, limits, and four regression tests. Swift suite: 175 tests,
one skipped, no failures. This does not complete steps 3–5; no host grants or
input authorization are changed. The native approval binding must not infer
bound-input capability from metadata support.

Native app-call v1 now validates exact installation and running code at operation
entry/capture, using a private capability and an optional required-binding mode.
Swift suite: 179 tests, one skipped, zero failures. Host grant integration is not
yet connected; per-event enforcement in long input operations, platform parity,
and native acceptance remain open. Unsigned/unverifiable code is refused by v1.

The embedding host now stores scoped app grants separately, resolves before and
after approval, and uses bound transport. The next native phase installs a
thread-scoped per-event identity guard. Targeted CGEvent and SkyLight dispatch
are first: each event revalidates the inspected process and signed code. Tests
inject an inert event sink to exercise full typing/dragging sequences without
native UI input. Accessibility mutations, global pointer dispatch, recovery
activation, cleanup of held input, and actual native acceptance remain required.

Targeted dispatch and Accessibility mutation guards now pass the Swift suite:
185 tests, one skipped, zero failures. Recovery validates before unhide/activate
and AX mutations and cannot reopen by bundle identifier in a bound operation.
Identity failures propagate as errors rather than triggering a fallback.
Global pointer hit-target checking, SkyLight focus mutation, held-input cleanup,
and native acceptance remain incomplete. The event-sink tests do not establish
foreground focus behavior, authentication, or delivery to an actual app.

Follow-up: missing thread scopes now refuse in required-binding mode. Global
pointer events check the AX hit owner before every dispatch; synthetic focus
checks retained process lifetime and onscreen window ownership on activation
and deactivation. The 190-test Swift run passed with one skipped. A further
shortcut regression fixes modifier-release flags so each release removes its
modifier before dispatch: 191 tests, one skipped, zero failures. All input tests
use inert sinks. Interrupted held-input cleanup, process-cancellation behavior,
capability finalization, platform parity, and native acceptance remain open.
