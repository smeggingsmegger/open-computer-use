# Nonprompting permission readiness

The Taffy host needs to inspect permission readiness without opening onboarding.
Added `permissions`, which prints the same diagnostic as `doctor` but never
presents onboarding. Both direct execution and the app-agent proxy preserve
that distinction. Existing `doctor` and default launch behavior are unchanged.
Validation: `swift test` passed (167 executed, 1 skipped, 0 failures). Native
permission acceptance remains blocked by the locked Mac.
