---
description: Fix PR comments
agent: build
---

Read the PR comments using `gh` cli. Ignore any comments that are outdated or resolved. There are two types of comments:

1. Comments from engineers
2. Comments from review bot

if the comment is from review bot and the severity is below medium you may use your best discernment to decide if it is worth fixing. 

EVERY OTHER COMMENT you should do what the comment says and fix the issue posed. 


After you are done addressing the issues please:
- commit and push the changes. Please use the git cli or the graphite cli depending on if the branch is tracked by graphite or not
- reply to each comment as appropriate.


current git branch: `git branch --show-current`
graphite branches: `gt log short`

