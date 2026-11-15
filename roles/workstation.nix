# NixOS desktop machine used by tmx.
{ inputs, outputs, configLib, ... }:

{
  imports = [
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager

    ../modules/shared/base
    ../modules/shared/sops
    ./agents.nix

    ../users/tmx/nixos.nix

    ../modules/nixos/desktop/base
    ../modules/nixos/desktop/bluetooth.nix
    ../modules/nixos/desktop/desktop
    ../modules/nixos/desktop/flatpak.nix
    ../modules/nixos/desktop/gaming.nix
    ../modules/nixos/desktop/streaming.nix
    ../modules/nixos/desktop/services
    ../modules/nixos/desktop/virtualization
    ../modules/nixos/desktop/filesystems
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs outputs configLib; };
  };
}
