# Structured observations for local decision callers

Add bounded, value-free element records alongside the existing snapshot text.
Keep cached target identity, mutation review, cancellation and app binding intact.
Taffy consumes the JSON envelope; old callers keep their first text and screenshot.
Do not parse rendered tree prose or expose secure fields to the decision model.
Validation: Swift snapshot serialization tests, Rust helper parsing, native fixture
acceptance after rebuilding/staging. Existing native action-review work is retained.
