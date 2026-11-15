# Review

Every hunk of the diff, grouped into sections and ordered top-down: from where the change is entered, down the call chain, with supporting code last.

```json
{ "sections": [{ "title": "string", "why": "markdown", "hunks": ["h3", "h7"], "pseudocode": ["string"], "folded": false }] }
```

## Order

1. The entry point: where the changed behaviour is reached from outside. For a backend change, the endpoint, route handler, job, consumer, CLI command or event listener. For a UI change, the place the new or changed component is used: the page or parent that renders it. For a library change, the public function its callers use. Wiring that makes the entry reachable (route or job registration, a component's import and use in its parent) goes here too. The first section's `why` says what the whole flow does, so a reader who stops there knows the shape of the change.
2. Down the call chain from there, depth-first: each section is what the one before it calls, in the order it is called. For example endpoint → service → repository → query, or page → component → hook → API client. With several entry points, finish one chain before starting the next, the main one first.
3. Supporting code: utilities, helpers, shared types, constants and schemas that the chain uses but that don't carry the flow. They go after everything that uses them.
4. Tests, grouped by the behaviour they cover.
5. Mechanical changes last: config, generated files, lockfiles, renames, formatting.

## Rules

- Place every hunk exactly once. The build fails on unknown, duplicated or unplaced hunks.
- Group by concern, not by file. Hunks from different files that implement one idea share a section, and one file's hunks may be split across sections.
- Within a section, order hunks the way the code runs: caller before callee.
- `title` names the concern ("Retry loop for webhook delivery"), not the file.
- `why` is 1-3 sentences on what the section does and where it sits in the chain (what calls it), plus anything easy to miss in the code. Don't narrate the diff line by line.
- Keep each section small enough to review in one sitting; split large ones.
- `pseudocode` feeds the Pseudocode tab; see its guide.
- `folded: true` starts a section's hunks folded. Use it for code nobody wrote by hand or that needs no line-by-line read: generated files, lockfiles, snapshots, pure renames and formatting. Keep those in their own section so the hand-written code stays unfolded.
