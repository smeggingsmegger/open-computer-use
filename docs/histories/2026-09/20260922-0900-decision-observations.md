# Structured decision observations

The Taffy Local Laya integration needs indexed controls without parsing the
rendered Accessibility tree. Snapshots now include an additive versioned JSON
text envelope with capture-time indices, roles, labels, and action names.
Field values, coordinates, and secure controls are excluded. Existing cached
identity checks and app binding remain authoritative for all mutations.

Source changes: AccessibilitySnapshot.swift, ComputerUseService.swift, and
DecisionObservation.swift. Swift and native validation are recorded in the
parent Taffy Local decisions acceptance ledger; no native claim is made here.

The additive envelope is also emitted by the Linux and Windows helpers. Linux
AT-SPI supplies editable/protected flags; Windows UIA supplies SetValue/IsPassword
flags. Go unit suites passed and both amd64 targets cross-compiled with the
checksum-verified official Go 1.27.1 toolchain. Linux Python tests passed. These
are compile/contract checks, not live Linux/Windows desktop acceptance. The
macOS Swift suite passed (214 tests, one skipped); a real signed native fixture
reached the OS Accessibility gate and refused before observation/mutation. The
Taffy Local acceptance ledger records the required user permission and retry.
