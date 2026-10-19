# Taffy native action review

User request: enforce meaningful target review while keeping local bots usable
and preserving app authorization, cancellation, and private user input.

Added in-memory, bounded Accessibility element identity evidence to snapshots.
App-bound indexed lookup refuses changed or unavailable evidence before using
the cached control. Error text requests fresh inspection without exposing the
observed values. Values are not persisted or logged.

Two inert ElementIdentityEvidenceTests passed and the helper compiled. These
compare metadata without live Accessibility or desktop input. The helper is not
staged by this change; live native acceptance remains pending. Prepared-action
review across focused keyboard and coordinate paths remains open, as documented
in the execution plan. This early check does not prove consequential-action
scope enforcement or final target revalidation.

Dispatch follow-up: direct indexed set-value, secondary actions, and direct AX
scroll steps now revalidate cached identity after app validation and before the
mutation. Cancellation during target review prevents dispatch. The callback is
mutation-local, so post-action inspection and release cleanup are unaffected.
Two inert regression cases cover changed control metadata, review lifetime, and
cancellation during review. The current Swift test invocation could not start
because Xcode requires license acceptance; these additions are uncompiled and
native acceptance is still pending. Click fallbacks and focused/coordinate
paths still need target review; this does not establish effect authorization.

Preferred AX click actions now pass target review through each repeated dispatch.
Containing-web-row actions check both the original control and the selected row.
List-selection checks the original control, list/item metadata, and the current
list/item relationship before writing selected children. An additional inert
regression checks that a control disappearing after the first action blocks the
second. These Swift changes remain uncompiled pending Xcode license acceptance;
coordinate/mouse, activation fallback and focused-key paths are still open.

Uncertain AX outcomes: bound mutation dispatch now throws on generic failure,
cannot-complete, or an invalidated target instead of returning these outcomes to
fallback click/typing paths. Error text requests fresh inspection and verification
before another action. Explicit action/attribute unsupported responses retain
fallback behavior. Inert regressions cover both action and attribute paths and
unsupported results. Native compilation and execution still require Xcode license
acceptance; no result from these new tests is claimed yet.


Native verification resumed after Xcode became available. The selected guard
suite passed 36 tests and the release helper compiled. Corrected a test-only
assumption: an unregistered command-line XCTest process can have AppKit PID -1;
current-process kernel evidence is now checked using getpid, with a separate
invalid-descriptor rejection check. Production lifetime checks are unchanged.
The initial selected run failed that assumption (34 passed, 1 failed); the
corrected run passed all 36. Native action acceptance remains pending.

Focused text entry now captures bounded control identity with the snapshot and
checks both the same Accessibility object and unchanged metadata before typing.
Direct value writes repeat the check after app validation; keyboard fallback
checks before dispatch and each new key-down. Key-up and held-input cleanup do
not inherit the review, and its lifetime ends before post-action snapshots.
Changed-focus, cancellation-during-review, and review-lifetime regressions pass:
27 selected Swift tests passed. These are inert dispatch tests, not native focus
acceptance. General press-key shortcuts, coordinate/activation targets, typed
effect assessment, and prepare/execute authorization remain open. Rebuild and
restage the helper before accepting these changes in the packaged app.

Full Swift verification after focused text changes: 208 tests executed, one
skipped, zero failures. The release helper was rebuilt and staged successfully.
The acceptance app still needs rebundling before native verification.

Shortcut dispatch now uses the same per-key-down review scope. Snapshots retain
bounded window identity alongside focused-control identity. A shortcut refuses
changed windows, changed metadata, and focus appearing or disappearing since
inspection. Window-level navigation remains available when both inspected and
current focus are absent. Cleanup releases still bypass target review. The full
Swift suite passed after this change; native window/focus acceptance and effect
authorization remain outstanding. This helper must be restaged and rebundled.

Targeted mouse-click dispatch now preserves its original error through the
service layer. The old catch replaced identity/cancellation failures with advice
to enable global pointer input, despite the delivery path already being chosen.
The full Swift suite passed (208 executed, one opt-in live test skipped). This
change does not complete coordinate target/effect review or native acceptance;
the packaged helper needs updating before verifying the new error presentation.

Activation-only indexed clicks now carry the cached control review through each
AXRaise, AXMain, and AXFocused mutation, after app identity validation. The
callback is required by the activation helpers, so this fallback cannot silently
omit target review. The full Swift suite passed: 208 executed, one opt-in test
skipped, zero failures. This closes the activation fallback omission, not the
remaining coordinate/mouse or consequential-effect authorization work. Native
acceptance requires the restaged helper in a rebuilt desktop app.

Indexed mouse click dispatch now retains a mutation-local target review across
public targeted, private targeted, and global paths. Each mouse-down rechecks
cached identity and unchanged control bounds; mouse-up and cleanup remain
available after the target changes. The review is also checked before preparing
the input operation and cancellation is checked after review. Two inert tests
cover all three delivery routes, a changed target before a second click,
cancellation during review, and review lifetime. Full Swift validation passed:
210 executed, one opt-in test skipped, zero failures. This is indexed mouse
coverage, not raw-coordinate/drag semantic authorization or native acceptance.
The helper must be rebuilt and restaged again before packaged verification.

Native AX hit-testing now treats its input as window points. Both callers
already supplied converted window coordinates; applying screenshot scaling a
second time could select another control on Retina captures. The call now uses
window-to-global translation directly. Full Swift validation passed (210 tests,
one opt-in skip, zero failures). Native Retina hit-test acceptance is still open.

Accessibility click fallback sequences now retain the original requested control
review at each AX mutation, in addition to the chosen descendant/list/row target
review. Nested scopes retain their outer checks and restore them on return or
failure. This prevents an unchanged child from receiving a fallback when its
original source changed. An inert regression covers unsupported first action,
changed source, blocked fallback, and scope cleanup. Full Swift suite: 211 tests,
one opt-in skip, zero failures. Native acceptance and restaging remain open.

Coordinate click dispatch now requires its hit-tested Accessibility object to
exist in the inspected snapshot. A mutation-local review checks its cached
identity, unchanged bounds, and current hit-test identity before Accessibility
mutations and mouse-down delivery. A replacement overlay or uninspected target
requires fresh inspection instead of implicitly gaining input authorization.
The same review spans AX-to-mouse fallback. This does not assess consequential
effects, authorize arbitrary canvas controls, or validate drag destinations.
A regression blocks mouse fallback when an unsupported AX action replaces the
coordinate target. Swift validation and native acceptance are tracked separately;
the helper must be restaged before a packaged app can contain this change.

Validation: the full Swift suite passed after the coordinate-review change: 212 tests, one opt-in test skipped, zero failures. Native acceptance is outstanding.

Control identity capture now includes AXURL, accepting native URL and string
representations with the same bounded in-memory evidence. Changing or removing
a link destination invalidates the inspected target even if its label remains
unchanged. Unsupported URL attributes remain valid for non-link controls;
unreadable, malformed, or oversized attributes cannot establish identity.
Regression coverage compares native URL/string representations and rejects
changed, removed, malformed, and oversized destinations. This is destination
identity checking, not host-side authorization of a link's effects.

Validation: the full Swift suite passed with 213 tests, one opt-in skip, zero failures. Native link acceptance remains open.

Drag initiation now resolves source and destination to inspected Accessibility
controls and rechecks both after app validation immediately before mouse-down.
Both use the coordinate target review and one screenshot-to-window conversion.
The original source geometry is not enforced after movement begins, because
movement itself may legitimately change it. A targeted/global inert regression
changes the destination during app validation and confirms no mouse-down or
dragged input is dispatched. Mid-gesture destination changes, drop-effect
assessment, and native drag acceptance remain outstanding; this is preflight
and press-time validation only.

Validation: full Swift suite passed with 214 tests, one opt-in skip, zero failures. Restaging and native drag acceptance remain outstanding.
