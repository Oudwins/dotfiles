# Step 2 - Split NixOS system config into modules

Goal: move `nixos/system/configuration.nix` content into larger, logical modules, keeping host-specific values in `nixos/hosts/<host>/default.nix`.

Actions:
- Create larger module files to avoid tiny fragments:
  - `nixos/modules/common/base/default.nix` (locale + nix config + nixpkgs settings)
  - `nixos/modules/common/sops/default.nix` (sops config)
  - `nixos/modules/common/users/tmx/default.nix` (tmx user config)
  - `nixos/modules/nixos/desktop/default.nix` (xserver, display manager, awesome, xkb, desktop-related packages, fonts)
  - `nixos/modules/nixos/services/default.nix` (flatpak, printing, avahi, pipewire, tailscale, teamviewer, journald, thunar, ratbagd)
  - `nixos/modules/nixos/virtualization/default.nix` (libvirtd, docker, spice, virtualization-related kernel params)
  - `nixos/modules/nixos/filesystems/default.nix` (nextcloud mount, tmpfiles, sudo rule)
- Keep host-specific values and any remaining settings that don't fit elsewhere in `nixos/hosts/<host>/default.nix` (e.g. hostname, boot params not tied to virtualization).
- Update `nixos/system/configuration.nix` to import the above modules and remove moved content.
- Ensure all moved settings are identical to avoid behavior change.

Verification:
- `nixos-rebuild build --flake .#nixos` succeeds.
- Optionally compare `nix eval .#nixosConfigurations.nixos.config.system.build.toplevel` before/after.
