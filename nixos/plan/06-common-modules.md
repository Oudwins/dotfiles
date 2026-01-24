# Step 6 - Consolidate shared modules

Goal: move shared settings into `modules/common` and `home/common`.

Actions:
- Identify overlapping config between nixos and darwin:
  - home-manager programs like git, direnv, starship
  - shell defaults
  - shared packages (if any)
- Move shared pieces into `nixos/modules/common/*` and `nixos/home/common/*`.
- Import common modules from both nixos and darwin hosts.

Verification:
- `nixos-rebuild build --flake .#nixos` succeeds.
- `darwin-rebuild build --flake .#macos` succeeds on mac host.
