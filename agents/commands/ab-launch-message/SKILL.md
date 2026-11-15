---
name: ab-launch-message
description: Draft the initial Slack launch message for an A/B test from its PostHog experiment and PRs.
disable-model-invocation: true
---

# A/B test launch message

Draft the message announcing that an A/B test has launched, for the user to paste into the growth experiments Slack channel. The reader is the wider growth team: they should understand what changed, why we think it will work, who sees it, and where to follow it, without opening any links.

The user may give a PostHog experiment URL or ID, one or more PR links, and/or a free-text description. If they give nothing, use the PR for the current branch (`gh pr view`) or the branch diff against the main branch.

## Process

1. Investigate before asking anything. Work out every section of the message yourself by querying whatever the test touches, and only then go to the user. Use executor for the MCP integrations, and read each tool's schema before calling it.
   - PostHog: from the experiment, get the name, description, variant keys and split, primary and secondary metrics, and linked feature flag; from the flag, get the rollout %, release conditions, and any flag dependencies. List the other running experiments and flags and check whether any target the same surface or users (for Collisions).
   - Code: read the PRs (`gh pr view`, `gh pr diff`) and the code around them. Find where the flag is evaluated to see what each arm actually does compared with today, which surfaces/routes it touches, what is unchanged, and how users are targeted or excluded. Look for comments, PR descriptions, or linked issues that explain the reasoning (for the "because").
   - Payload: for marketing-site and landing-page tests, read the A/B test and page entries for the control/variant URLs, the split and the variant content.
   - Slack: search the growth experiments channel for earlier tests on the same surface. These give prior evidence for the hypothesis and show running tests or promos that could collide.
   - Anything else the test clearly touches: follow it.
2. Check your findings with the user in a single message:
   - List what you found and where it came from: the inferred hypothesis (change, primary metric, guardrail, "because"), the arms and split, eligibility and exclusions, and collisions. Ask the user to confirm or correct it.
   - Then ask only for what you could not find or infer.
   Never present an inference as fact in the draft without the user confirming it. Don't invent anything; leave a clear placeholder if the user doesn't know.
3. Draft the message in the format below, using the confirmed answers, and give it to the user in a code block so it can be copied. Then list the screenshots they need to attach, one per variant that has a `[screenshot]` placeholder.
4. Iterate on the wording when asked. Never post to Slack.

## Format

```
*[Test launched: <short name>]*
<Optional: 1-2 lines on what changes vs today and what stays the same.>

*Hypothesis*
If we <specific change>, then <named primary metric> will <direction> without <guardrail getting worse>, because <why this audience behaves this way> [// <evidence from a prior test>].

*Variants*
• Control (<x>%) - <short description, usually "today's <thing>">
    ◦ Preview: <url or [screenshot]>
• <Arm name> (<y>%) - <short description>
    ◦ Preview: <url or [screenshot]>

*Eligibility*
• <who enters the test, when the test is limited to a subset of users>
• Excluded: <who> (<why>)

*Collisions*
• <overlap with another running test or promo, and how it's handled>

*Monitoring*
• Experiment: [<label>](<url>)
• Dashboard: [<label>](<url>)
• PRs: [<repo>#<number>](<url>)
```

### Sections

- **Title**: `Test launched:` followed by a short, plain name for the change (e.g. "Mobile checkout layout", "MW /pricing vs Pricing LP (Search)"). Put the channel or audience in parentheses when it matters. Use `(Retest)` for re-runs.
- **Summary line** (optional): include it only when the title doesn't already make the change obvious. Say what the variant does compared with today and what is not changing (e.g. "Desktop is unchanged.", "Prices and paid plans are unchanged."). For a retest or follow-up, use this line for the context instead (e.g. "Retest: the original was skewed by a redirect bug.", "Follow-up to [this win](<url>).").
- **Hypothesis**: one sentence, two at most, in the If / then / because form.
  - Name the specific change. If there are several, name the one or two that matter rather than listing every change.
  - Name the primary metric as it appears in the experiment ("sign-up rate", "API key creation rate", "paid within 7 days"), not just "conversion".
  - Always include the guardrail in the sentence ("without lowering revenue per visitor", "even if sign-up rate softens"). If you can't find one, ask the user; if they don't know, leave a placeholder.
  - The "because" explains the user's motivation or the friction being removed, not a restatement of the change.
  - Add prior evidence after `//` only when there is a concrete earlier result to point to.
  - For tests that expect no effect, say so: "not showing X will not reduce Y".
  - Don't say what we'll do if the test wins.
- **Variants**: one bullet per arm, in the experiment's order, control first. Use the variant names people will recognise (the flag keys capitalised, e.g. "Stacked", "Compact"), not "Variation 1". The percentages are each arm's share of the experiment, taken from PostHog. Each description is a short phrase covering what that arm shows. For split-URL tests the preview is the page URL; for UI changes it is a `[screenshot]` placeholder. Leave out the section only when there is nothing to say beyond the summary line.
- **Eligibility**: include it only when the test is limited to a subset of users. State the rollout when it isn't 100% ("20% of eligible users enter"), the targeting (platform, plan, route, trigger condition), and each exclusion with its reason. Don't mention 100% rollout or "all users".
- **Collisions**: include it only when the test overlaps with another running test or promo. Name the other test and how it's handled ("Not exposed together with the annual pricing test", "Same arm as the in-app version via a flag dependency", "Runs independently of the in-app version").
- **Monitoring**: links only. Leave out any line with nothing to link.

## Style

- Plain, concrete, present tense: "Free workspaces now see…", "The dialog is replaced with…". Use numbers for allocation and baselines.
- Put routes, events and flag keys in backticks (`/checkout`).
- Use single asterisks for section headers, `•` / `◦` for bullets, and no emojis.
- Keep it short. If a line doesn't help someone understand or follow the test, cut it.
- Every fact (split, rollout, metrics, URLs) must come from the sources or the user.

## Examples

In-product test:

```
*[Test launched: Mobile checkout layout]*
On mobile web, the checkout page keeps the Pay button on screen. Desktop is unchanged.

*Hypothesis*
If mobile visitors always have the Pay button in view, then checkout completion will increase without lowering average order value, because today the button sits below the order summary and scrolls out of view.

*Variants*
• Control (34%) - today's single-column checkout
    ◦ Preview: [screenshot]
• Stacked (33%) - collapsible order summary, sticky Pay bar
    ◦ Preview: [screenshot]
• Compact (33%) - one-screen summary with an inline Pay button
    ◦ Preview: [screenshot]

*Eligibility*
• Mobile web visitors to `/checkout`
• 20% of eligible visitors enter

*Monitoring*
• Experiment: [Checkout layout experiment](<experiment url>)
• PRs: [app#123](<pr url>)
```

Split-URL landing page test:

```
*[Test launched: MW /features vs Photo Editor LP (Meta)]*
The photo editor ads currently land on the general /features page. This splits them between /features and a photo-editor-specific LP.

*Hypothesis*
If we send the photo editor Meta ads to a photo-editor-specific LP instead of the general /features page, then sign-up rate will increase without lowering paid conversion, because the ad sells one outcome and the LP delivers it in the first screen with a single call to action // the matching LP won on search last month.

*Variants*
• Control (50%) - marketing site /features page
    ◦ Preview: <control url>
• Variant (50%) - photo editor LP
    ◦ Preview: <variant url>

*Monitoring*
• Experiment: [Photo editor LP experiment](<experiment url>)
```
