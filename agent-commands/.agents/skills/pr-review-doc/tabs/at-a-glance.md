# At a glance

What the PR does and why, readable in under a minute.

```json
{ "tldr": "markdown", "problem": "markdown" }
```

- `tldr`: 2-5 bullets. Lead with what changes in behaviour or structure, then the main mechanism, then anything the reviewer must know before reading the code (migrations, feature flags, breaking changes, follow-ups left out). Describe the change, not the files.
- When the PR follows a pattern already in the codebase, say so in `tldr`: name the closest existing example and how this PR departs from it, if at all. That is what the reviewer needs to check.
- `problem`: one short paragraph on the problem being solved and how things behaved before. Take it from the PR description and linked issues; if they don't say, infer it from the code and say that it is inferred.
