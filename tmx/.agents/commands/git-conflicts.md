
# Resolve Merge Conflicts <!-- omit in toc -->

Your job is to resolve merge conflicts in the current branch of the current repo.

## 1. Preparation

Assume I already ran:

```bash
git checkout main
git pull
git checkout <current_branch>
git rebase main
```

If this command is being invoked, there are unresolved merge conflicts you need to fix.

## 2. Build context

1. Run `git diff main` to understand the changes in this branch relative to `main`.
2. Run `rg "<<<<<<<"` to find all merge conflicts.

## 3. Resolve conflicts

For each conflict, decide whether to:

1. Keep **our** changes (the current branch)
2. Keep **their** changes (`main`)
3. Use a careful, intelligent combination of both

In most cases you should aim for (3), but correctness matters more than cleverness.

When you are confident about how to resolve a conflict:

1. Edit the file to the desired final state
2. Remove all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
3. Save the file and run any relevant checks or tests if practical
4. Stage the resolved files with `git add`

## 4. Once all conflicts are resolved
Please continue the rebase with `git rebase --continue` and start back at step 2 until there are no more conflicts


## Very Important: Don't be afraid to ask for help

If you are not sure how a conflict should be resolved, stop and ask me for direction or clarification.

1. Show me the conflicting chunks
2. Explain what you believe you should do
3. Wait for confirmation

Now go resolve the conflicts.

