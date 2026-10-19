# Taffy Local integration fork

This fork preserves the Open Computer Use patches used by Taffy Local.

- Upstream: https://github.com/iFurySt/open-computer-use
- Fork: https://github.com/smeggingsmegger/open-computer-use
- Integration branch: `codex/taffy-integration`
- Base: upstream v0.3.5, `386a260d1ab8b690adbbb27f7471595cf0c2b752`

The integration branch contains passive permission readiness, installed-app and
process identity binding, cached-control validation, cancellation and held-input
cleanup, and structured decision observations on macOS, Linux, and Windows.
The existing execution plans and histories describe implementation boundaries
and outstanding native acceptance. Committing these patches does not complete
the unfinished action-effect authorization work.

Taffy Local pins an exact integration commit in its
`vendor/open-codex-computer-use` submodule. The directory keeps its historical
name for build-script compatibility. The fork's `main` tracks the newer upstream
line; it is not the Taffy integration branch. Upstream upgrades are separate
integration work and must preserve Taffy's private host contracts.

## Updating the integration

Keep `origin` pointed at this fork and `upstream` pointed at iFurySt's repository.
Fetch both remotes before publishing. Commit and push helper changes to
`codex/taffy-integration`, then commit the updated submodule pin in Taffy Local.
Do not use submodule ignore settings to conceal uncommitted helper changes, or
advance the pin with `git submodule update --remote`.

After changing checkouts, run `git submodule sync --recursive` and
`git submodule update --init --recursive` in Taffy Local. A clean checkout uses
only the committed fork revision; no local patch application is required.

Verification for this migration: `swift test` passed (215 tests, one opt-in
skip), and the three Linux Python runtime tests passed. Go is not installed in
the migration environment, so neither Go suite was rerun. Native desktop
acceptance is not established by these tests.
