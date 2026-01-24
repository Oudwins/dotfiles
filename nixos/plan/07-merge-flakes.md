# Step 7 - Merge darwin flake into main flake

Goal: keep a single flake at `nixos/flake.nix` with both nixos and darwin configurations.

Actions:
- Copy darwin inputs/outputs into `nixos/flake.nix`.
- Wire `darwinConfigurations.macos` to `nixos/hosts/darwin`.
- Keep nixos on `nixos-25.11` and point darwin to `nixpkgs-unstable`.
- Remove `nixos/darwin/flake.nix` and `nixos/darwin/flake.lock` when the new flake works.

Verification:
- `nix flake show` from `nixos/` lists both `nixosConfigurations` and `darwinConfigurations`.
- `nixos-rebuild build --flake .#nixos` succeeds.
- `darwin-rebuild build --flake .#macos` succeeds on mac host.
