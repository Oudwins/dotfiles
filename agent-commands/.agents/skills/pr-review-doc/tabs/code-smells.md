# Code smells

A quick check of the added and changed code for patterns the user dislikes. Only report what the PR introduces or changes, never existing code around it.

```json
{
  "summary": "markdown, optional",
  "items": [
    {
      "title": "Fetch error is logged and swallowed",
      "kind": "try-catch",
      "severity": "high | medium | low",
      "note": "markdown",
      "refs": [{ "hunk": "h5", "lines": [30, 38] }]
    }
  ]
}
```

## Checks

- `try-catch`: new `try`/`catch` blocks, especially ones that swallow errors, log and continue, return a default, or wrap a single call that could let the error propagate to a boundary.
- `loose-types`: `any`, `as` casts, non-null `!`, `@ts-ignore`, `Record<string, any>`, `unknown` passed along without narrowing, `string` where a union fits, optional fields that are always set, and explicit types where inference would do.
- `tiny-functions`: functions with a one- or two-line body that only rename or forward a call, add indirection without explaining anything, and are used once or twice.
- `data-mapping`: data copied or reshaped between near-identical types, fields renamed on the way through, the same data kept in two places, or transformations a single source of truth would avoid.
- `client-fetching`: frontend code fetching data on the client (`useEffect` with `fetch`, a client query on mount) in an app that renders on the server, such as the Next.js app router or Remix. Check the framework first; this does not apply to SPAs.
- `async-waterfall`: independent `await`s run one after another instead of together, `await` inside loops, and components that wait for a parent's data before starting their own fetch.
- `other`: anything else the repo's `AGENTS.md`, `CLAUDE.md` or lint config rules out.

For the mechanical checks, search the added lines (`git diff <merge base> <head> -U0 | grep '^+'`), or use `ast-grep` via `nix shell nixpkgs#ast-grep`, then read each hit in context before reporting it.

## Writing items

- One item per occurrence, or one item with several `refs` when the same smell repeats.
- `note`: why it is a problem here and what to do instead, in one or two sentences.
- `severity`: `high` hides failures or will likely cause a bug; `medium` should change before merge; `low` is a nit.
- An empty `items` list is fine; the tab is then hidden.
