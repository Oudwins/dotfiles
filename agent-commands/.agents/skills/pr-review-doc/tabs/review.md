# Review

Every hunk of the diff, grouped into sections and ordered so the reviewer reads the heart of the change first.

```json
{ "sections": [{ "title": "string", "why": "markdown", "hunks": ["h3", "h7"], "pseudocode": ["string"] }] }
```

## Order

1. The heart of the change: the main entry point, main loop or core function where the new behaviour lives. Someone who reads only this section should understand what the PR does.
2. What the heart depends on: new types, contracts, schemas and helpers, in the order the heart uses them.
3. What calls into the heart: wiring, routes, registration, the UI that triggers it.
4. Tests, grouped by the behaviour they cover.
5. Mechanical changes last: config, generated files, lockfiles, renames, formatting.

## Rules

- Place every hunk exactly once. The build fails on unknown, duplicated or unplaced hunks.
- Group by concern, not by file. Hunks from different files that implement one idea share a section, and one file's hunks may be split across sections.
- Within a section, order hunks the way the code runs: caller before callee.
- `title` names the concern ("Retry loop for webhook delivery"), not the file.
- `why` is 1-3 sentences on what the section does and how it connects to the heart, plus anything easy to miss in the code. Don't narrate the diff line by line.
- Keep each section small enough to review in one sitting; split large ones.
- `pseudocode` feeds the Pseudocode tab; see its guide.
