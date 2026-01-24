# Step 3 - Split NixOS home-manager config

Goal: move `nixos/home.nix` into larger home-manager modules, mirroring the grouping approach from Step 2.

Actions:
- Create larger modules to avoid tiny files:
  - `nixos/home/common/base/default.nix` (home basics like username, homeDirectory)
  - `nixos/home/common/shell/default.nix` (direnv, starship, bash config, shell helpers)
  - `nixos/home/common/git/default.nix` (git settings)
  - `nixos/home/nixos/desktop/default.nix` (rofi, mpv, mimeApps, themes)
  - `nixos/home/nixos/packages/default.nix` (home.packages grouped by purpose)
  - `nixos/home/nixos/services/default.nix` (syncthing, redshift, udiskie, flameshot, espanso)
- Keep session variables in the host-specific config to make host-level overrides easier.
- Keep host-specific settings (including `home.stateVersion` and session variables) and anything that doesn’t fit a shared module in `nixos/home.nix`.
- Update `nixos/home.nix` to import these new modules.

Verification:
- `nixos-rebuild build --flake .#nixos` succeeds.
- `home-manager build --flake .#tmx@nixos` succeeds (optional if available).
