# Pseudocode

The Review tab's sections with pseudocode first, so the reviewer can follow the logic and then open each file's diff underneath. There is no separate file: write it as `pseudocode` on the sections in `review.json`.

```json
{
  "sections": [
    {
      "title": "Retry loop for webhook delivery",
      "why": "...",
      "hunks": ["h3", "h7"],
      "pseudocode": ["for each pending delivery:", "  POST payload with signature header", "  on 5xx: schedule retry with backoff"]
    }
  ]
}
```

- The tab shows each section with pseudocode, followed by its hunks grouped by file and folded. Sections without pseudocode, such as lockfiles or formatting, are left out of the tab.
- Each entry is one line of pseudocode. Indent nested steps with two spaces per level, and keep the code's own names for functions, types and fields.
- Describe what the code does, including branches, loops, early returns, error paths and side effects (writes, network calls, events). Leave out syntax, imports and plumbing.
- Cover every hunk in the section, in the same order, so the code below reads as the expansion of the steps above it.
- 3-15 lines per section. Split a longer section in the Review tab rather than flattening it.
