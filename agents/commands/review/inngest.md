# Review inngest code

Consult the docs for best practices in addition to this document.

## Errors

- validates event data inline instead of using a helper like `eventType`
- **Put every side effect inside `step.run`.** The function body re-runs for each step, so a DB write, API call or send outside a step runs more than once.
- **Make every step idempotent.** Steps retry, so each must be safe to run twice. Pass an idempotency key derived from the event to external APIs that accept one.
- **Commit database writes before calling a foreign system.** Persist local state in its own step before calling an external API, and treat sending events or queue messages as a call that can fail.
