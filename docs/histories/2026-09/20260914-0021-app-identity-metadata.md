# Private app identity metadata

Implement the metadata prerequisite for host app authorization without treating
metadata support as permission to control an app.

- Added versioned private `taffy/app-identity` RPC with an exact query schema.
  Initialize advertises `taffy/appIdentityMetadata` separately from input tools.
- Exact app paths, bundle identifiers, and names resolve to canonical candidates.
  Distinct copies remain ambiguous; canonical aliases deduplicate. Name scans
  have a three-second/20,000-entry limit and results are limited to eight copies.
- Metadata includes canonical bundle/executable paths and offline Security
  framework signature validation, designated requirement, team identifier, and
  code-directory hash. Unsigned, invalid, unavailable, and ad-hoc signatures are
  distinct from valid signatures. Missing signing evidence fails closed.
- Response size is bounded to 1 MiB. Lookup does not launch apps, inspect their
  windows, or request permissions. No provider tool or authorization was added.
- Tests cover copy ambiguity, alias deduplication, unsigned inert fixtures,
  structured transport/unknown-field refusal, separate capability negotiation,
  and offline metadata from a real signed system executable.

The Swift suite has 175 tests, one skipped, no failures. Native focus/prompt
acceptance is still pending. Bound input, dynamic process signing checks, host
scoped grants, and Windows/Linux support remain open in the execution plan.
