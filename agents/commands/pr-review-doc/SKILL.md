---
name: pr-review-doc
description: Build a keyboard-driven HTML review page for a pull request, ordered by what matters, with live GitHub review threads.
disable-model-invocation: true
argument-hint: "<PR url or number> [tabs]"
---

# PR review doc

Build a review page for a colleague's pull request, so the user can understand and review it from the keyboard. The page is a set of tabs. Each tab has a guide in `tabs/` and a schema in `scripts/schema.ts`. `pr-review-server` serves the page on `http://127.0.0.1:7457` and proxies the PR's review threads to and from GitHub.

Paths below are relative to this skill's directory.

## Process

1. Resolve the PR from the user's URL or number. Without one, use the PR for the current branch (`gh pr view --json url`). Note any tabs the user names, e.g. "quick view and risks".
2. Get a checkout of the PR's repo: the current repo if it matches, otherwise find or clone it. Fetch the base branch and the PR head (`git fetch origin <base> pull/<number>/head`) so both commits exist locally. Leave the user's working tree alone; read the head with `git show <oid>:<path>` or a separate `git worktree`.
3. If `node_modules` is missing, run `bun install --cwd <this skill's directory> --frozen-lockfile`.
4. Run `bun scripts/prepare.ts <pr url> --repo <checkout>`. It writes `<workdir>/pr.json` with the full diff, and prints the workdir and every hunk with its id (`h1`, `h2`, ...). When the workdir already has a page, it also says whether the diff changed since then. A rebase that leaves the diff alone needs no new tabs: skip to step 7. The page only says the PR has changed when its diff has.
5. Read the PR description, linked issues, the diff and the surrounding code at the head commit until you understand the change. Note which parts are backend and which are frontend; the tab guides say what to look for in each.
6. Write the tabs to `<workdir>/tabs/<tab id>.json`, reading each one's guide first. If the user named tabs, write At a glance, Review and the named tabs; leave out At a glance and Review too only when the user says to build only the named ones. Otherwise use the table below and your judgement. Write the Review tab before the others, since its order is the one the rest follow.
7. Run `bun scripts/build.ts <workdir>`, with `--tabs <id>,<id>` listing the tabs you wrote if the user named tabs, so the page has only those. Fix every problem it reports and rebuild until it prints the page URL. `--tabs` also builds just one tab while you iterate on it.
8. Open the URL. In T3 Code, call `preview_open` with `reuseExistingTab: false`; elsewhere run `open <url>`. If `curl -sf <url>` fails, the server is not running: tell the user to enable `services.pr-review-server` in the nix config rather than starting it yourself.

Reply with the URL, the tabs you left out and why, and anything you could not work out. The page holds the review, so don't repeat it in chat.

## Tabs

| Tab | File | When |
|---|---|---|
| [At a glance](tabs/at-a-glance.md) | `at-a-glance.json` | Always |
| [Quick view](tabs/quick-view.md) | `quick-view.json` | Always |
| [Review](tabs/review.md) | `review.json` | Always |
| [Pseudocode](tabs/pseudocode.md) | `pseudocode.json` | The PR has backend logic: branches, loops, async work, state changes, error handling or side effects. Most useful when that logic is complex. Leave it out for frontend-only PRs and for backend logic the diff already makes obvious |
| [Architecture](tabs/architecture.md) | `architecture.json` | The PR changes how modules, services or components connect in a way the diff doesn't make obvious, or adds several parts that work together |
| [Data model](tabs/data-model.md) | `data-model.json` | Schemas, migrations, persisted shapes, core types or store state change |
| [Interfaces](tabs/interfaces.md) | `interfaces.json` | Contracts change: stored or wire shapes (schemas, routes, events, config), or interfaces unrelated code uses |
| [Code smells](tabs/code-smells.md) | `code-smells.json` | Always; the tab is hidden when it has no items |
| [Performance](tabs/performance.md) | `performance.json` | Queries, hot paths, loops doing I/O, rendering of large lists, bundle size or caching change |
| [Risks](tabs/risks.md) | `risks.json` | Always; the tab is hidden when it has no items |

## Code references

Tabs point at code with `{ "hunk": "h3", "lines": [12, 20] }`. `lines` are new-file line numbers as shown in the diff, or old-file numbers for removed code; leave `lines` out to show the whole hunk. The removed lines that a referenced addition replaces are included. The page renders references as real diff lines, so the user can comment on them in any tab. The build rejects references to lines outside the hunk.

## Writing tab content

- Markdown fields render as GitHub-flavoured markdown. Put paths, symbols, routes and flags in backticks.
- Write for a reviewer who has not seen the PR: concrete, plain, present tense, no filler.
- Every claim must come from the PR, its code or its linked issues. Say so when something is inferred.
- Only report problems you can point to in the code. A short accurate tab beats a long speculative one.
