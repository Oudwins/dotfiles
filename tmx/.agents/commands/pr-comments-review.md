---
description: Address PR comments
agent: build
---

Read the PR comments using `gh` cli. Ignore any comments that are outdated or resolved. Respond with a list of comments in the following format:

code_line: {{code line/s for the comment }}
comment: {{description/explanation - should contain sufficient detail for someone that has not read the comment to understand.}}
code_samples: {{ code sample/s showcasing the area of code the comment is referencing with just enough context to understand }}
is_correct: {{use your critical thinking to determine if this is correct/has merit or not & explain why}}
proposed_fix: {{only if is_correct=true, then explain proposed fix briefly, minimal code examples encouraged. Focus on the APIs/architecture}}


Then ask me which we should fix. Make sure to read the appropriate files when verifying if a comment has merit. 

