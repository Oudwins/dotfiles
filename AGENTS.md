## What is this repo
This repo contains dotfiles for user.

Breakdown of key directories:
```bash
# this holds the nixos configuration for the system
nixos/* 
# this holds the dotfiles and is symlinked recursively tmx/* to ~/
# So tmx/.config becomes ~/.config
tmx/* 
```

## Configuration management

- Nix configuration lives in `nixos/` and primarily manages packages and services.
- Most application settings are **not managed by Nix**. Store them under `tmx/`
  using the same relative path they should have in the user's home directory.
  For example, `tmx/.config/app/config.yaml` becomes `~/.config/app/config.yaml`.
- GNU Stow creates symlinks from the home directory to these files; it does not
  move or copy them. Run `./updateSymlinks.sh` from this repository to apply them.
  The script runs `stow -d tmx -t ~ .` from `~/dotfiles`.
- Keep mutable settings in the Stow-managed files rather than generating them
  with Nix/Home Manager, unless that application's configuration is explicitly
  Nix-managed already. Do not manage the same path with both Stow and Nix.
- Files containing credentials should remain Git-ignored. Track a starter template
  instead, keeping the actual settings file local and ignored. Keep generated
  OAuth credentials outside the Stow tree.
