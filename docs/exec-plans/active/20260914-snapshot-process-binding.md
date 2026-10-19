# Bind cached snapshots to their process

Status: in progress. Part of the host app-identity authorization work.

The service currently returns cached snapshots without checking the process and
silently captures a new snapshot if an input call has no cache entry. Input must
instead require explicit inspection, reject exited/replaced processes, and clear
all aliases of stale snapshots. Capture launch time and executable identity when
the app descriptor is created. Recheck metadata without resolving by name or
launching apps before returning cached state for input.

Tests cover missing inspection on all input entry points, stale incarnation
comparisons, and alias invalidation. Run Swift unit tests and build the helper.
Native app restart/focus acceptance remains separate and is not established by
these tests. Stable signed identity approval, transport capability negotiation,
and platform parity remain further work; this guard is not a saved grant.

Implementation complete for the operation-entry guard. Kernel proc_pidinfo and
proc_pidpath are used because AppKit launch metadata was incomplete for the real
unit-test process. Swift validation: 171 tests, one skipped, no failures; helper
build passed. Native restart/focus acceptance and stronger final-event identity
binding remain pending. Keep this plan active until native acceptance is recorded.
