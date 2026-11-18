# Review

Every hunk of the diff in one list, ordered so it reads top-down: from where the change is entered, down the call chain, with supporting code last.

```json
{ "hunks": ["h3", "h7", "h1"], "folded": ["h1"] }
```

## Order

1. The entry point: where the changed behaviour is reached from outside. For a backend change, the endpoint, route handler, job, consumer, CLI command or event listener. For a UI change, the place the new or changed component is used: the page or parent that renders it. For a library change, the public function its callers use. Wiring that makes the entry reachable (route or job registration, a component's import and use in its parent) goes here too.
2. Down the call chain from there, depth-first: each hunk is what the one before it calls, in the order it is called. For example endpoint → service → repository → query, or page → component → hook → API client. With several entry points, finish one chain before starting the next, the main one first.
3. Supporting code: utilities, helpers, shared types, constants and schemas that the chain uses but that don't carry the flow. They go after everything that uses them.
4. Tests, next to each other and in the order of the code they cover.
5. Mechanical changes last: config, generated files, lockfiles, renames, formatting.

## Rules

- Place every hunk exactly once. The build fails on unknown, duplicated or unplaced hunks.
- Order by the flow, not by file. One file's hunks may be far apart.
- `folded` lists hunks that start folded. Use it for code nobody wrote by hand or that needs no line-by-line read: generated files, lockfiles, snapshots, pure renames and formatting. Test files start folded anyway.
