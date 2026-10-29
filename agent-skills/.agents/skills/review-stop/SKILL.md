---
name: review-stop
description: Trigger this if the user says 'review stop'.
---

# Review Stop

Send a PR to a human reviewer and watch it until their review comes in. Then
stop and report it. Do not change the PR, reply to comments, or merge.

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

Report the PR link and each reviewer's verdict. If they left comments, read
`~/.agents/skills/pr-comments-review/SKILL.md` and follow it. The "review
stop" request authorizes running it. End by asking which comments to fix, as
it says. Do not fix them yourself.
