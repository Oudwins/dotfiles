---
name: review-stop
description: Trigger this if the user says 'review stop'.
---

# Review Stop

Send a PR to a human reviewer and watch it until their review comes in. If
the approvals it has are enough for GitHub to merge it and nobody left
feedback, merge it. Otherwise stop and report the review. Do not change the PR
or reply to comments, except for the restack in "Stacked PRs".

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

Ignore CI, bot, and base branch events, except a PR below this one merging
(see "Stacked PRs"), and required checks finishing (for example a policy
bot) after an approval without feedback. When an event needs no action, end
your turn without a message.

## Act on each review

Feedback means a review that requests changes, a review body, or inline or
conversation comments.

- **Feedback:** stop once each reviewer you wait on has submitted a review
  (approved, changes requested, or commented), and report it. See "Report
  feedback".
- **No feedback so far:** after each approval, and when a required check
  finishes after one, check whether the repo's rules
  allow the merge now: branch protection or rulesets, and a policy bot's
  status check if the repo has one (`gh pr view --json
  reviewDecision,mergeStateStatus,statusCheckRollup`). If they do, merge,
  even while other reviewers have not reviewed yet. If they need more
  approvals, keep waiting.
- **Stacked:** if the PR's base is another PR's branch, it cannot merge yet.
  Keep waiting until every PR below it has merged. See "Stacked PRs".

In T3 Code, call `unwatch_pull_request` before you report feedback or ask.

## Merge

The "review stop" request authorizes the merge. Before merging, run
`git fetch` and check the PR again: required checks are green, it is not
BEHIND or DIRTY, and GitHub reports it as mergeable. Merge on GitHub with
`gh pr merge`, never a local merge and push. Use the method the repo uses,
through branch protection as configured. Never use `--admin` or other
bypasses. If it cannot merge, do not fix it, apart from the restack in
"Stacked PRs". Report why and stop.

Report the PR link, each reviewer's verdict, and the merge commit.

## Stacked PRs

Never merge a PR into its parent's branch. While PRs below it are open, also
watch the lowest one, and keep acting on reviews of this PR as above. When it
merges, move the watch to the next unmerged PR below. Once every PR below has
merged, restack this PR onto the default branch: `gt sync` and `gt restack`
for a Graphite stack, otherwise rebase and `gh pr edit --base`. Push with
`--force-with-lease`. If the restack conflicts, report it and stop. Then merge
as above. If the push dismissed the approval, wait for a new one.

## Report feedback

When a review has feedback, report the PR link and each reviewer's verdict.
If they left comments, read `~/.agents/skills/pr-comments-review/SKILL.md`
and follow it. The "review stop" request authorizes running it. End by asking
which comments to fix, as it says. Do not fix them yourself.
