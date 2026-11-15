---
name: commit
description: Create focused git commits for the current changes without agent attribution.
disable-model-invocation: true
---

# Commit Changes

You are tasked with creating git commits for the changes made during this session.

## Process:

1. **Think about what changed:**
   - Review the conversation history and understand what was accomplished
   - See the results for git status and diff below.
   - Consider whether changes should be one commit or multiple logical commits

git status:
Run `git status` and use its output.

git diff:
Run `git diff` and use its output.

2. **Plan your commit(s):**
   - Identify which files belong together
   - Draft clear, descriptive commit messages
   - Use imperative mood in commit messages
   - Focus on why the changes were made, not just what

3. **Explain your commit plan:**
   - List the files you plan to add for each commit
   - Show the commit message(s) you'll use

4. **Execute the commits:**
   - Use `git add` with specific files (never use `-A` or `.`)
   - Create commits with your planned messages
   - Show the result with `git log --oneline -n [number]`

## Important:
- **NEVER add co-author information or Claude attribution**
- Commits should be authored solely by the user
- Do not include any "Generated with Claude" messages
- Do not add "Co-Authored-By" lines
- Write commit messages as if the user wrote them
- Do not ask for confirmation from the user to create the commits. Just create them

## Remember:
- You have the full context of what was done in this session
- Group related changes together
- Keep commits focused and atomic when possible
- The user trusts your judgment - they asked you to commit
