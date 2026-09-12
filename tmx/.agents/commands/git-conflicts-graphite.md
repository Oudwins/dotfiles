---
name: git-conflicts-graphite
description: Fix git conflicts during Graphite CLI commands
agent: build
---

# Resolve Graphite Merge Conflicts

Your job is to resolve merge conflicts.

## 1. Preparation

Determine if there is an active conflict.

if no active conflict then most likely this branch has conflict with main before it can be merged. So run `gt sync` / `gt restack` to sync with origin and surface the conflict.


Graphite normally shows this kind of message when a conflict appears:

```text
Hit conflict restacking <branch> on main.

Unmerged files:
<file>

To fix and continue your previous Graphite command:
(1) resolve the listed merge conflicts
(2) mark items as resolved by adding them one at a time with gt add <file>
(3) run gt continue to continue executing your previous Graphite command
It's safe to cancel the ongoing rebase with gt abort.
```

## 2. Build Context

1. Run `git status` to see the current rebase/restack state and unmerged files.
2. Run `gt status` if available to understand the current stack and where Graphite stopped.
3. Run `rg "<<<<<<<"` to find all conflict markers.
4. Inspect the conflicted files and relevant surrounding code before editing.

## 3. Resolve Conflicts

For each conflict, decide whether to:

1. Keep the current branch's changes
2. Keep the incoming/base changes
3. Use a careful, intelligent combination of both

In most cases you should aim for (3), but correctness matters more than cleverness.

When you are confident about how to resolve a conflict:

1. Edit the file to the desired final state
2. Remove all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
3. Save the file and run any relevant checks or tests if practical
4. Mark the resolved file with `gt add <file>`

Prefer `gt add <file>` over `git add <file>` during Graphite conflict flows because Graphite's own continuation state expects the Graphite command workflow.

## 4. Continue The Graphite Command

Once all current conflicts are resolved and marked with `gt add <file>`, run:

```bash
gt continue
```

If `gt continue` hits another conflict, start back at step 2. Graphite restacks can surface conflicts branch-by-branch, so expect to repeat this loop until the original Graphite command completes.

If you need to cancel the in-progress Graphite operation, use:

```bash
gt abort
```

Do not use `git rebase --continue` or `git rebase --abort` unless I explicitly ask you to leave the Graphite workflow.

## Very Important: Don't Be Afraid To Ask For Help

If you are not sure how a conflict should be resolved, stop and ask me for direction or clarification.

1. Show me the conflicting chunks
2. Explain what you believe you should do
3. Wait for confirmation

Now go resolve the Graphite conflicts.
