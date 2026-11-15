---
name: review-stop
description: Trigger this if the user says 'review stop'.
---

# Review Stop

Send a PR to a human reviewer and watch it until their review comes in. If
every reviewer approves without feedback, merge it. Otherwise stop and report
the review. Do not change the PR or reply to comments.

## Request review

Use the PR the user gave, or the PR for the current branch. Request review
from the colleagues the user named, mapping names to GitHub usernames with the
user's mappings. Without names, wait on the reviewers already requested. If
nobody is requested, ask the user who should review.

Request review with `gh pr edit --add-reviewer`. Never ping reviewers in
comments.

## Wait for the review

Use one watcher, as described in `babysit-pr`:

- In T3 Code, call `watch_pull_request` and end your turn.
- Elsewhere, wait with `pr-wait --until any-change`. Start it again after it
  times out or exits on an event that is not the review.

Ignore CI, bot, and base branch events. When an event is not the review, end
your turn without a message.

## Stop when the review arrives

Stop once each reviewer you wait on has submitted a review on GitHub
(approved, changes requested, or commented). In T3 Code, call
`unwatch_pull_request` first.

## Merge when there is no feedback

No feedback means every reviewer you wait on approved, with no review body and
no inline or conversation comments. Then merge. The "review stop" request
authorizes it. Before merging, run `git fetch` and check the PR again: required
checks are green, it is not BEHIND or DIRTY, and GitHub reports it as
mergeable. Merge on GitHub with `gh pr merge`, never a local merge and push.
Use the method the repo uses, through branch protection as configured. Never
use `--admin` or other bypasses. If it cannot merge, do not fix it. Report why
and stop.

Report the PR link, each reviewer's verdict, and the merge commit.

## Report feedback

Otherwise, report the PR link and each reviewer's verdict. If they left
comments, read `~/.agents/skills/pr-comments-review/SKILL.md` and follow it.
The "review stop" request authorizes running it. End by asking which comments
to fix, as it says. Do not fix them yourself.
