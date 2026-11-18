# Pseudocode

The PR's logic as pseudocode, grouped into sections, so the reviewer can follow it and then open each file's diff underneath.

```json
{
  "sections": [
    {
      "title": "Retry loop for webhook delivery",
      "why": "...",
      "pseudocode": ["for each pending delivery:", "  POST payload with signature header", "  on 5xx: schedule retry with backoff"],
      "hunks": ["h3", "h7"]
    }
  ]
}
```

- Write sections only for code with logic: branches, loops, async work, state changes, error handling or side effects. Leave out declarative code, where steps would only restate the diff: config, schemas, registration, types, markup and styling, generated files, lockfiles, formatting. Hunks may be left out. Leave the file out when no code has logic.
- Order sections and their hunks as in the Review tab.
- Group by concern, not by file. `title` names the concern ("Retry loop for webhook delivery"), not the file.
- `why` is 1-3 sentences on what the section does and where it sits in the chain (what calls it), plus anything easy to miss in the code. Don't narrate the diff line by line.
- The tab shows each section's pseudocode, followed by its hunks grouped by file and folded.
- Each entry is one line of pseudocode. Indent nested steps with two spaces per level, and keep the code's own names for functions, types and fields.
- Describe what the code does, including branches, loops, early returns, error paths and side effects (writes, network calls, events). Leave out syntax, imports and plumbing.
- Cover every hunk in the section, in the same order, so the code below reads as the expansion of the steps above it.
- 3-15 lines per section. Split a longer section rather than flattening it.
