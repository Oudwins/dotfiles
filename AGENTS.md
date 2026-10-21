## What is this repo
This repo contains dotfiles for user.

Breakdown of key directories:
```bash
# this holds the nixos configuration for the system
nixos/* 
# this holds the dotfiles and is symlinked recursively tmx/* to ~/
# So tmx/.config becomes ~/.config
tmx/* 
# Separate Stow packages for automatic skills and manually invoked commands.
# Both contribute to ~/.agents/skills; Claude uses the same collection.
agent-{skills,commands}/*
```

## Configuration management

- Nix configuration lives in `nixos/` and primarily manages packages and services.
- Most application settings are **not managed by Nix**. Store them under `tmx/`
  using the same relative path they should have in the user's home directory.
  For example, `tmx/.config/app/config.yaml` becomes `~/.config/app/config.yaml`.
- GNU Stow creates symlinks from the home directory to these files; it does not
  move or copy them. Run `./updateSymlinks.sh` from this repository to apply them.
  The script restows `tmx`, `agent-skills`, and `agent-commands` from its own
  checkout. All three are packages in the same Stow directory so their shared
  destination directories can merge.
- Agent skills and commands are an exception to the `tmx/` source layout:
  store them in `agent-skills/.agents/skills/<name>/` and
  `agent-commands/.agents/skills/<name>/`, respectively. Both use
  `SKILL.md`; commands also require `disable-model-invocation: true` in its
  frontmatter and `policy.allow_implicit_invocation: false` in
  `agents/openai.yaml`. Keep directory names and skill names identical.
  Each package also needs a `.claude/skills/<name>` symlink pointing to
  `../../.agents/skills/<name>` so Claude discovers the same entry.
- Keep mutable settings in the Stow-managed files rather than generating them
  with Nix/Home Manager, unless that application's configuration is explicitly
  Nix-managed already. Do not manage the same path with both Stow and Nix.
- Files containing credentials should remain Git-ignored. Track a starter template
  instead, keeping the actual settings file local and ignored. Keep generated
  OAuth credentials outside the Stow tree.
