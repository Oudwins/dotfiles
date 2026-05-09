---
description: Create git commits with user approval and no Claude attribution + PR
agent: build
---

# Commit Changes

You are tasked with creating git commits for the changes made during this session.

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

1. Analyze the diff content to understand the nature and purpose of the changes
2. Generate 3 commit message candidates based on the changes
   - Each candidate should be concise, clear, and capture the essence of the changes
   - Prefer Conventional Commits format (feat:, fix:, docs:, refactor:, etc.)
3. Select the most appropriate commit message from the 3 candidates and explain the reasoning for your choice
4. Stage changes if necessary using git add
5. Execute git commit using the selected commit message
6. Push the branch to the remote repository
7. Create a PR with the github cli


## Commit Format

`<type>: <description>`

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `perf`: Performance
- `test`: Tests
- `chore`: Build/tools

**Rules:**

- Imperative mood ("add" not "added")
- First line <72 chars
- Atomic commits (single purpose)
- Split unrelated changes

## Creating a PR

```bash
# use github cli to create the PR. Example command below
gh pr create --base main --head feature-branch --title "Your PR title" --body "Detailed description of the changes"
```

Remember to use the head branch from the git repo (generally main or master) to target the PR against. It should be the following: !`git remote show origin | grep "HEAD"`

## Constraints

- DO NOT add co-authorship footer to commits
- DO NOT add any mention of yourself to commits, descriptions, titles, etc.
