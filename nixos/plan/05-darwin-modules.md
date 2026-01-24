# Step 5 - Split Darwin config into modules

Goal: refactor the darwin config into `nixos/modules/darwin` and `nixos/home/darwin` using the same conventions as steps 1-4 (module folders with `default.nix`, no misc bucket, host-specific values stay in host files).

Actions:
- Create module folders under `nixos/modules/darwin/` and wire them through `nixos/modules/darwin/default.nix`:
  - `base/default.nix` (nix settings, nixpkgs config, programs.zsh, fonts, system.defaults)
  - `pkgs/default.nix` (environment.systemPackages)
  - `pkgs/homebrew/default.nix` (homebrew enable + onActivation + casks + brews)
  - `services/default.nix` (launchd agents, aerospace if enabled)
- Update `nixos/hosts/darwin/default.nix` to import `../../modules/darwin` and keep host-specific values (system.stateVersion, system.primaryUser, users.users.tmx.home, home-manager backup extension).
- Split `nixos/hosts/darwin/home.nix` into modules under `nixos/home/darwin/` and reuse `nixos/home/common/*` for shared config:
  - `nixos/home/darwin/default.nix` imports darwin home modules
  - `nixos/home/darwin/shell/default.nix` (programs.zsh initContent)
  - `nixos/home/darwin/packages/default.nix` (home.packages)
  - Move `home-files/aerospace.nix` into a darwin home module if still needed
  - Keep `home.username`, `home.homeDirectory`, `home.stateVersion`, and `home.sessionVariables` in `nixos/hosts/darwin/home.nix`

Verification:
- `darwin-rebuild build --flake .#macos` succeeds on mac host.
- `nix flake show` still works on linux host.
