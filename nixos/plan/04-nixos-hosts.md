# Step 4 - Introduce NixOS host folder

Goal: move host-specific files under `nixos/hosts/nixos` while keeping flake usage unchanged.

Actions:
- Create `nixos/hosts/nixos/default.nix` and move host-specific imports there.
- Move `nixos/system/hardware-configuration.nix` to `nixos/hosts/nixos/hardware-configuration.nix`.
- Fold `nixos/system/vm.nix` into `nixos/modules/nixos/virtualization/default.nix` and remove duplicates.
- Update `nixos/system/configuration.nix` imports to the new paths, or update the flake to point at `nixos/hosts/nixos` if preferred.
- Keep `nixos/flake.nix` unchanged for now unless a host-level import is required.

Verification:
- `nixos-rebuild build --flake .#nixos` succeeds.
