# Risks

What could go wrong when this ships, and what the reviewer should check before approving.

```json
{
  "summary": "markdown, optional",
  "items": [
    {
      "title": "Migration locks the deliveries table",
      "kind": "optional label, e.g. data, rollout, security",
      "severity": "high | medium | low",
      "note": "markdown",
      "refs": [{ "hunk": "h2" }]
    }
  ]
}
```

Look for:

- Data: migrations that are slow, lock tables, can't be rolled back, or need a backfill; writes that can corrupt or lose data.
- Rollout: deploy order between services, old clients against the new server, feature flags and their defaults, config or secrets that must exist first.
- Correctness: race conditions, retries that are not idempotent, partial failures, time zones, error paths that leave state half-written.
- Security: missing authorisation checks, unvalidated input, secrets in code or logs, data exposed to the wrong users.
- Blast radius: shared code with many callers, behaviour changes callers may not expect.
- Gaps: changed behaviour without tests, missing logs or metrics to tell whether it works in production.

- `note`: what can go wrong, who it affects, how likely it is, and what to check or change. Point `refs` at the code involved.
- `severity`: `high` can cause an outage, data loss or a security issue; `medium` can cause user-facing bugs; `low` is worth a look.
- An empty `items` list is fine; the tab is then hidden.
