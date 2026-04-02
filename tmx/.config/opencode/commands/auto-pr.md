---
description: Do task then autocommit and PR
agent: build
---

# Auto PR 

You are tasked with completing the user's request, commiting the changes and creating a PR with them.

## Process

1. Understand the users query
2. Research the codebase
3. Verify that the code changes work
4. Commit the changes
5. Call the simplifier agent to review your changes and address its concerns
6. Commit changes
7. Push the branch to the remote repository
8. Create a PR with the github cli


## Creating the changes

- Follow existing codebase patterns
- Always make the SMALLEST or most MINIMAL change you can to address the request unless specifically told to make bigger changes

## Commit & PR instructions

### Commit Process

1. Analyze the diff content to understand the nature and purpose of the changes
2. Generate 3 commit message candidates based on the changes
   - Each candidate should be concise, clear, and capture the essence of the changes
   - Prefer Conventional Commits format (feat:, fix:, docs:, refactor:, etc.)
3. Select the most appropriate commit message from the 3 candidates and explain the reasoning for your choice
4. Stage changes if necessary using git add
5. Execute git commit using the selected commit message


### Commit Format

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

### Creating a PR

```bash
# use github cli to create the PR. Example command below
gh pr create --base main --head feature-branch --title "Your PR title" --body "Detailed description of the changes"
```

Remember to use the head branch from the git repo (generally main or master) to target the PR against. It should be the following: !`git remote show origin | grep "HEAD"`

### Constraints

- DO NOT add co-authorship footer to commits
- DO NOT add any mention of yourself to commits, descriptions, titles, etc.


-----
