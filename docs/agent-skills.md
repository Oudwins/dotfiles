# Agent commands and skills

Commands and automatically selected skills live in two folders:

- `agents/commands/<name>/`: manually invoked commands.
- `agents/skills/<name>/`: ordinary skills.

Each directory contains `SKILL.md` with `name` and `description` frontmatter,
plus any supporting files. Commands additionally set
`disable-model-invocation: true` in that frontmatter and include
`agents/openai.yaml` containing:

```yaml
policy:
  allow_implicit_invocation: false
```

Run `./updateSymlinks.sh` to link every entry of both folders into
`~/.agents/skills/<name>` and `~/.claude/skills/<name>`, exposing the same
collection to Codex and Claude Code. Invoke commands
with `/name` in Claude Code or `$name` in Codex. Pi's prompts link points only to
the commands folder through `home-files/tmx/.agents/commands`; its directory-prompts
extension provides `/name` commands with companion-file support.

Edit the source folder directly; nothing is generated or copied. Use matching
kebab-case directory and skill names, unique across both folders. After adding or
removing an entry, run `./updateSymlinks.sh`.

The former
`research_basic` and `research_basic_inline` prompts are now `research-basic`
and `research-basic-inline`. Existing filename-based names are otherwise kept.
Use ordinary user instructions for inputs and ask the agent to run shell commands
as part of the workflow rather than relying on client-specific substitutions.
OpenCode's commands link is retained, but directory-format commands are not
adapted for OpenCode.

The script Stow-links `home-files/tmx` into `~`, then links the agent entries.
It creates `~/.agents/skills` and `~/.claude/skills` as real directories first so
Stow never folds them into the checkout, and it removes dangling links that point
into this checkout (left behind when files move); unrelated files in the home
directory remain subject to Stow's normal conflict checks.
Git-ignored untracked files are excluded automatically; tracked files remain
included. Normal Stow directory folding is retained: ignored files inside a
linked directory remain accessible through that link. Preview changes with
`./updateSymlinks.sh --simulate`.


## Imported tstack skills

Imported from [t3dotgg/tstack](https://github.com/t3dotgg/tstack/tree/1085050f3baed1ac724caa4a8166145fb2ac88af/skills), with MIT licenses included:

All seven are ordinary skills in `agents/skills/`: `babysit-pr`,
`council`, `file-pr`, `full-send`, `full-stop`, `leaving-pr-comments`, and `sol-loop`.

`modernize` and `takeover` are intentionally excluded.
