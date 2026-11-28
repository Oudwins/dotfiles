---
name: review
description: Review code using the bundled React, TypeScript, and Inngest review guidance.
disable-model-invocation: true
---

# Review code

Review the changes or files identified by the user. If no scope is supplied,
review the current working tree diff.

Read the relevant companion guidance relative to this skill directory:

- [General](general.md) for all code.
- [TypeScript](typescript-generic.md) for TypeScript code.
- [React](react.md) for React components and hooks.
- [Inngest](inngest.md) for Inngest workflows and event handling.
- [Migrations](migrations.md) for database schema and data migrations.
- [Feature flags](feature-flags.md) for code that adds or checks feature flags.

Guides group their rules under Errors and Flags:

- **Errors** are always issues. Report each one as a finding.
- **Flags** are judgement calls. List them after the findings as questions
  for the user to confirm; don't count them as findings.

Report findings and flags with file paths and line numbers. Explain the
problem and its effect; state when no actionable findings were found.

