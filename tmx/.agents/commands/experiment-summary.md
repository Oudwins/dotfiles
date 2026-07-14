---
name: experiment-summary
description: Fetch a PostHog experiment's primary metrics via MCP and draft a Slack-style results message for the team.
---

# Experiment results summary

You are tasked with pulling a PostHog experiment's results and turning them into a concise, emoji-led Slack message the user can paste straight to their team.

The user will give you an experiment reference (a PostHog experiment URL, an experiment ID, or a name). They may also tell you which metrics matter most (e.g. "sign ups and contact sales, subscriptions less important"). If they don't, ask once, then proceed.

## Process

<SOP>
1. Resolve the experiment ID.
   - From a URL like `https://<region>.posthog.com/project/<project>/experiments/<id>` the `<id>` is the experiment ID.
   - If given only a name, use the PostHog MCP to find it (`experiment-get-all` / `experiment-list`).
2. Fetch the data via the PostHog MCP server. ALWAYS read the tool's JSON descriptor/schema before calling it.
   - `experiment-get` — variants (control + test variants), status, start/end dates, metric definitions.
   - `experiment-results-get` — the actual metric results (`metrics.primary.results`, `metrics.secondary.results`). The large payload is written to a file; read it.
3. Map the variant keys to human-readable labels using the experiment description (e.g. `transcript-player` = "non-interactive, plays transcripts"). Refer to test variants as "Variation 1, 2, ..." in the message but keep the variant key + plain-English descriptor next to each.
4. For each metric you care about, compute the per-variant result vs the `control` baseline:
   - Funnel conversion rate = final `step_counts` / `number_of_samples` (use the funnel denominator when the metric is a 2-step funnel).
   - Relative delta = (variant_rate − control_rate) / control_rate, expressed as a %.
   - Record significance from the `significant` flag and sanity-check the `credible_interval` (an interval that crosses 0 is effectively not significant even if flagged — call this out).
   - Skip metrics whose `data` is `null` (query failed / not enough data).
5. Decide the emoji per point based on the metric's goal:
   - :large_green_circle: improvement in the desired direction
   - :red_circle: regression in the desired direction
   - :white_circle: flat / no meaningful movement
6. Draft the message (see format below) and present it to the user for tweaks. Iterate on wording/emoji as requested.
</SOP>

## Reporting rules

- Lead with the metrics the user said matter most. Put the strongest, clearly-significant wins first.
- When highlighting a "win" metric (e.g. Contact Sales), only report figures that are **statistically significant**. Drop non-significant variants of that metric, or mark them `(ns)` if context needs them.
- Be honest: if the headline signup/primary metric is down, say so. Don't dress up a regression.
- Keep numbers consistent with what PostHog shows. Round deltas to one decimal or whole % as appropriate.
- Note whether the experiment is still running vs ended, and frame the message accordingly ("following up after ~N days").

## Message format

- Casual, first-person team-update voice. Short.
- One intro line giving context (experiment, days running, what's being tested).
- A bold header per test variation, then one point per line, with a blank line between each point (renders cleanly in Slack).
- A short closing read (1-3 sentences): which variation wins, the trade-off, and the next step.
- End with a link to the experiment.

### Emoji conventions (use Slack shortcodes, not unicode)

- `:large_green_circle:` positive / win
- `:red_circle:` negative / regression
- `:white_circle:` flat / neutral

### Template

```
Hey team following up on the <experiment> experiment after ~<N> days. Here's how the variations did vs control:

**Variation 1 — <variant-key> (<plain-english descriptor>)**

:large_green_circle: +X% <Metric> (sig)

:red_circle: -Y% <Metric> (sig)

:white_circle: -Z% <Metric> (flat)

**Variation 2 — <variant-key> (<plain-english descriptor>)**

:large_green_circle: +X% <Metric> (sig)

:red_circle: -Y% <Metric> (sig)

:white_circle: -Z% <Metric> (flat)

<1-3 sentence read: winner, trade-off, next step.>

Full results: <experiment url>
```

## Constraints

- Do NOT invent metrics or numbers — every figure must come from the MCP results.
- Always read the MCP tool schema before calling it.
- Present the message in plain text the user can copy; don't wrap the final message in extra commentary beyond what's useful for editing.
