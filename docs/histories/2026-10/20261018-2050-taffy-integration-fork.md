# Preserve Taffy Local patches on a published fork

The user requested a real fork with the existing patches committed so the
Taffy Local submodule can be clean without hiding worktree changes.

Preserved the existing patch files on the original v0.3.5 base, created the
`codex/taffy-integration` branch, and documented fork ownership and the parent
pin workflow in `FORK.md`. No helper source changes were made by this migration.
Upstream and fork remotes were fetched; the newer upstream main was deliberately
kept separate from the currently integrated helper version.

Validation: Swift tests passed (215 tests, one opt-in skip), and Linux Python
runtime tests passed (3 tests). Go suites could not run because Go is unavailable.
The preserved plans retain their existing unfinished native acceptance and
semantic authorization work.
