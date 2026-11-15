{
  config,
  pkgs,
  configLib,
  lib,
  inputs,
  ...
}@args:

{
  imports = [
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "modules/nixos/hardware/disko/simpleDisko.nix")
    {
      _module.args = {
        disk = "/dev/sda";
        inherit lib;
        specialArgs = args;
      };
    }
  ];

  # Hetzner Cloud instances are KVM guests; keep the guest agent available
  # for console/recovery operations without inheriting local desktop defaults.
  services.qemuGuest.enable = true;
  systemd.services.qemu-guest-agent.path = [ pkgs.shadow ];

  boot.loader.grub = {
    enable = true;
  };

  networking.networkmanager.enable = lib.mkForce false;
}
