# Step 1 - NixOS layout scaffold

Goal: create the new module directory structure without changing behavior.

Actions:
- Create directories:
  - `nixos/modules/common`
  - `nixos/modules/nixos`
  - `nixos/modules/darwin`
  - `nixos/home/common`
  - `nixos/home/nixos`
  - `nixos/home/darwin`
- Add empty `default.nix` aggregators where helpful (can be stubs for now).

Verification:
- `nix flake show` from `nixos/` succeeds.
- `nixos-rebuild build --flake .#nixos` succeeds.
