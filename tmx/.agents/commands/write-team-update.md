---
name: write-team-update
description: Reconcile work across Linear, GitHub, agent sessions, and Slack, then write a team update
agent: build
---

Write a short team update about my work, using the Linear MCP, GitHub CLI, local OpenCode and Pi conversations, and Slack MCP. First gather activity and deduplicate it into tasks, then reconcile Linear, then write the update. This command includes creating and updating Linear issues and linking PRs, not just suggesting those changes.

## Gather activity

Use my local timezone and determine my identity in each service. Read all relevant results, including pagination, within these windows:

- Linear MCP: read my active issues and issues resolved since the previous update. Updates are on Wednesday and Friday: Wednesday covers (Friday, Wednesday], and Friday covers (Wednesday, Friday], with the previous update day exclusive and the current day inclusive. On other days, use the most recent preceding Wednesday or Friday as the exclusive boundary. Include ongoing work even if its issue was created before this window.
- GitHub CLI: check all PRs I created or merged since that boundary, across relevant repositories, as well as my still-open PRs. Read PR descriptions, linked issues, review state, and merge state to understand the work and its current status.
- OpenCode and Pi: discover their local session stores and read conversations with activity in the last 24 hours, across projects. Select by conversation activity, not just creation time, and read enough context to understand what I actually worked on and any associated repositories, branches, PRs, or issues. Use session content and outcomes, not just titles or proposed plans, as evidence of work.
- Slack MCP: read messages I sent in the last 7 days. Read relevant thread context to identify work I did, progress, blockers, and links to PRs or Linear issues. Distinguish my work from other people's work I merely mentioned.

The wider Slack window provides context and helps discover missing work; it does not extend the resolved-items window. If a source is unavailable, mention the coverage gap briefly rather than treating it as having no activity.

## Deduplicate into tasks

Build one combined task list before making Linear changes or drafting the update. Match work across Linear, GitHub, agent sessions, and Slack using issue IDs, PR URLs, repositories/branches, and the actual goal and scope of the work. Search Linear for matching issues, including unassigned and completed issues, before creating anything. Do not rely on titles alone or combine unrelated work just because it has a similar title.

Keep one entry per distinct task, collecting all supporting evidence and relevant PRs. Several sessions, messages, or PRs for the same task should produce one update entry and reuse the existing Linear issue. Preserve genuinely separate existing issues. Include concrete work, not casual conversation or hypothetical ideas that were never taken up.

## Reconcile Linear using the Linear MCP

For each deduplicated task:

1. Reuse the matching Linear issue. If there is none, create an issue in the appropriate team/project, assign it to me, and give it a concise title and evidence-based description with relevant source links. Infer the team/project from the repository and related issues; ask if it cannot be determined reliably.
2. Connect every applicable GitHub PR to the Linear issue using the MCP's supported PR-linking or attachment tools. Check existing links first so rerunning this command does not create duplicate issues or attachments. If the MCP cannot create a native PR association, attach the PR URL using the supported Linear link mechanism and clearly report that limitation.
3. Fetch the team's workflow states and update the issue to the appropriate actual state based on the latest evidence:
   - Completed/measuring: the task is complete or explicitly measuring outcomes. A merged PR is evidence of completed implementation, but do not mark the whole issue complete if related PRs or required work remain unfinished.
   - In review: the required implementation is ready for review in an open, non-draft PR, with no evidence of remaining implementation work.
   - In progress: work has started, including work in agent sessions, draft PRs, or remaining implementation work.
   - Todo: planned work that has not started.
   - Blocked: explicitly blocked according to the issue or recent evidence; do not infer a blocker from inactivity.
   A closed, unmerged PR is not evidence of completion. Resolve conflicting signals using the latest substantive evidence; if the status remains unclear, leave an existing issue's status unchanged and flag the uncertainty.
4. Verify the resulting issue, links, and status. Report failed or unsupported changes rather than claiming they succeeded.

Examples:
- An OpenCode/Pi session shows work on a task with no PR or Linear issue: create a Linear issue and set it to In Progress.
- A Linear issue and a PR describe the same task but are not linked: link the PR to that issue and move the issue to the appropriate status.
- Slack, two agent sessions, and several PRs describe the same task: reuse or create one issue, link all applicable PRs, and write one update entry.

## Write the update

Use the reconciled task list and verified Linear states. Keep each description short and grounded in the evidence, following the example below. Prefix each entry with its state emoji and group entries in this order:

:resolved: -> completed/measuring
:review: -> in review
:hourglass_flowing_sand: -> in progress
:to-do: -> todo
:no_entry: -> blocked

Only include resolved work completed since the previous update boundary. Creating or updating an issue now for older completed work does not make that work newly completed. For blocked items, include the task name and leave the explanation for me unless the reason is explicit in the sources.

The output is for Slack: use plain text with Slack formatting, not Markdown headings or Markdown-style links. For every task that has PRs, include all applicable PR links regardless of status, with only the PR number as the label: <https://github.com/owner/repo/pull/123|#123>. For multiple PRs, include each link, for example <https://github.com/owner/repo/pull/123|#123> <https://github.com/owner/repo/pull/456|#456>.

Return the draft for me to send. If there are coverage gaps or unresolved reconciliation problems, note them separately from the copyable update.


Example update: 
```txt
:resolved:  Termline cluster membership overrides system. Initial PR sets up must be connected overrides. We will also require must not be connected and must be root.  Of those, the second will be tricky have some ideas but want to discuss with @Mihail Feraru (thank you for always dealing with my crazy ramblings)
:review: Twilio hardening checklist progress. I'm sending a PR to XI and with that we should be good. Although there is no way to manually trigger the twilio alerts so I left one alert at very low to test and doesn't seem to have triggered.... Other than this everything is setup, we have XI using the new twilio project for verify and using a new phone number I purchased there. I also figured out the issue with n8n....

:hourglass_flowing_sand: More termline missing table permissions terraform PR. Some more work needs to be done for this. Speaking to Stav & Alex Holt. Huge thank you to @Gergely Bihary for your help!
:hourglass_flowing_sand: Ship one sample sfx page via termline. I think I will pick something since Rich is out to test.
:hourglass_flowing_sand: Help @Dorian with auth for vertex for elevenhacks

:to-do: Explore a way to have preseeded agent conversations. No progress here yet
:to-do: Investigate issue with EL not being able to send you to contact sales
```
