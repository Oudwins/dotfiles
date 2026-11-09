# Performance

Where the PR could get slow, and at what scale.

```json
{
  "summary": "markdown, optional",
  "items": [
    {
      "title": "One query per delivery when listing endpoints",
      "kind": "optional label, e.g. query, rendering, bundle",
      "severity": "high | medium | low",
      "note": "markdown",
      "refs": [{ "hunk": "h7" }]
    }
  ]
}
```

- Backend: N+1 queries, new queries without an index, unbounded queries or missing pagination, I/O inside loops, large payloads, slow work on the request path that could be deferred, and missing timeouts on external calls.
- Frontend: re-renders from unstable props or context, rendering of large lists, new dependencies or large imports added to the bundle, request waterfalls, heavy computation on the main thread, and layout thrashing.
- `note`: what happens, at what size it starts to matter (rows, items, requests per second), and the cheapest fix. Estimate from the code; say when you can't tell how large the input gets.
- `kind` groups items in the tab. Use a few short labels.
- Leave out micro-optimisations that don't change behaviour at realistic sizes.
